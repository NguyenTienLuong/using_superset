import logging
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import func, case, or_
from app.db.session import get_db
from app.db.models import Logs, Translation, File, Domain, StatusEnum, RequestTypeEnum

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("/dashboard/stats")
def get_dashboard_stats(
    date_from: str = Query(None),
    date_to: str = Query(None),
    domain_id: int = Query(None),
    model: str = Query(None),
    page: int = Query(1, ge=1),
    db: Session = Depends(get_db),
):
    logger.info(f">>> PARAMS: date_from={date_from} date_to={date_to} domain_id={domain_id} model={model}")

    try:
        per_page = 50
        dt_from = f"{date_from} 00:00:00" if date_from else None
        dt_to   = f"{date_to} 23:59:59"   if date_to   else None

        # ═══ BASE QUERY: lọc theo ngày ═══
        base_query = db.query(Logs)
        if dt_from and dt_to:
            base_query = base_query.filter(Logs.request_time.between(dt_from, dt_to))

        # ═══ Áp dụng filter domain/model bằng EXISTS + correlate ═══
        if domain_id or model:
            conditions = []

            if domain_id:
                # EXISTS: log có translation thuộc domain này
                trans_exists = (
                    db.query(Translation.trans_id)
                    .filter(
                        Translation.trans_id == Logs.translation_id,
                        Translation.domain_id == domain_id,
                    )
                    .correlate(Logs)   # bắt buộc để SQLAlchemy biết correlate với Logs
                    .exists()
                )
                # EXISTS: log có file thuộc domain này
                file_exists = (
                    db.query(File.file_id)
                    .filter(
                        File.file_id == Logs.file_id,
                        File.domain_id == domain_id,
                    )
                    .correlate(Logs)
                    .exists()
                )
                # Gộp IS NOT NULL vào điều kiện để tránh NULL comparison
                conditions.append(
                    or_(
                        (Logs.translation_id.isnot(None)) & trans_exists,
                        (Logs.file_id.isnot(None)) & file_exists,
                    )
                )

            if model:
                model_exists = (
                    db.query(Translation.trans_id)
                    .filter(
                        Translation.trans_id == Logs.translation_id,
                        Translation.model_name == model,
                    )
                    .correlate(Logs)
                    .exists()
                )
                conditions.append(
                    (Logs.translation_id.isnot(None)) & model_exists
                )

            if conditions:
                base_query = base_query.filter(*conditions)

        # ═══ Preload lookup tables ═══
        # available_domains: LUÔN toàn bộ, dùng cho dropdown
        available_domains = db.query(Domain).order_by(Domain.domain_id).all()
        available_models  = db.query(Translation.model_name).distinct().all()

        # display_domains: dùng cho chart/bảng phân bố
        if domain_id:
            display_domains = [d for d in available_domains if d.domain_id == domain_id]
        else:
            display_domains = available_domains

        # domain_map: tra tên nhanh theo id
        domain_map = {d.domain_id: d.domain_name.value for d in available_domains}

        # ═══ 1. Tổng thống kê (tính lại theo base_query đã filter) ═══
        total_requests = base_query.count()
        success_count  = base_query.filter(Logs.status == StatusEnum.success).count()
        error_count    = base_query.filter(Logs.status == StatusEnum.error).count()
        pending_count  = base_query.filter(Logs.status == StatusEnum.pending).count()
        success_rate   = round(success_count / total_requests * 100, 1) if total_requests > 0 else 0.0

        stats = {
            "total_requests": total_requests,
            "success_count":  success_count,
            "failed_count":   error_count,
            "pending_count":  pending_count,
            "success_rate":   success_rate,
        }

        # ═══ 2. Phân bố domain ═══
        trans_domain_rows = (
            base_query
            .join(Translation, Logs.translation_id == Translation.trans_id)
            .group_by(Translation.domain_id)
            .with_entities(
                Translation.domain_id,
                func.count(Logs.log_id).label("request_count"),
                func.sum(case((Logs.status == StatusEnum.success, 1), else_=0)).label("success_count"),
                func.sum(case((Logs.status == StatusEnum.error,   1), else_=0)).label("error_count"),
            )
            .all()
        )
        file_domain_rows = (
            base_query
            .join(File, Logs.file_id == File.file_id)
            .group_by(File.domain_id)
            .with_entities(
                File.domain_id,
                func.count(Logs.log_id).label("request_count"),
                func.sum(case((Logs.status == StatusEnum.success, 1), else_=0)).label("success_count"),
                func.sum(case((Logs.status == StatusEnum.error,   1), else_=0)).label("error_count"),
            )
            .all()
        )

        domain_counts: dict[int, dict] = {}
        for row in trans_domain_rows + file_domain_rows:
            did = row.domain_id
            if did is None:
                continue
            if did not in domain_counts:
                domain_counts[did] = {"request_count": 0, "success_count": 0, "error_count": 0}
            domain_counts[did]["request_count"] += row.request_count
            domain_counts[did]["success_count"] += row.success_count
            domain_counts[did]["error_count"]   += row.error_count

        domain_distribution = []
        for dom in display_domains:
            d = domain_counts.get(dom.domain_id)
            if d:
                domain_distribution.append({
                    "domain_name":   dom.domain_name.value,
                    "request_count": d["request_count"],
                    "success_count": d["success_count"],
                    "failed_count":  d["error_count"],
                    "percentage":    round(d["request_count"] / total_requests * 100, 1) if total_requests > 0 else 0.0,
                })
            else:
                domain_distribution.append({
                    "domain_name":   dom.domain_name.value,
                    "request_count": 0,
                    "success_count": 0,
                    "failed_count":  0,
                    "percentage":    0.0,
                })

        # ═══ 3. Failed stats ═══
        fail_total = error_count
        fail_rate  = round(fail_total / total_requests * 100, 2) if total_requests > 0 else 0.0

        fail_type_rows = (
            base_query
            .filter(Logs.status == StatusEnum.error)
            .group_by(Logs.request_type)
            .with_entities(Logs.request_type, func.count(Logs.log_id).label("count"))
            .all()
        )
        by_type = [
            {
                "request_type": r.request_type.value if r.request_type else "unknown",
                "count":        r.count,
                "percentage":   round(r.count / fail_total * 100, 1) if fail_total > 0 else 0.0,
            }
            for r in fail_type_rows
        ]

        fail_trans_domain_rows = (
            base_query
            .join(Translation, Logs.translation_id == Translation.trans_id)
            .filter(Logs.status == StatusEnum.error)
            .group_by(Translation.domain_id)
            .with_entities(Translation.domain_id, func.count(Logs.log_id).label("count"))
            .all()
        )
        fail_file_domain_rows = (
            base_query
            .join(File, Logs.file_id == File.file_id)
            .filter(Logs.status == StatusEnum.error)
            .group_by(File.domain_id)
            .with_entities(File.domain_id, func.count(Logs.log_id).label("count"))
            .all()
        )
        fail_domain_counts: dict[int, int] = {}
        for row in fail_trans_domain_rows + fail_file_domain_rows:
            did = row.domain_id
            if did is None:
                continue
            fail_domain_counts[did] = fail_domain_counts.get(did, 0) + row.count

        by_domain = []
        for dom in display_domains:
            count = fail_domain_counts.get(dom.domain_id, 0)
            if count > 0 or domain_id:
                by_domain.append({
                    "domain_name": dom.domain_name.value,
                    "count":       count,
                    "percentage":  round(count / fail_total * 100, 1) if fail_total > 0 else 0.0,
                })

        failed_stats = {
            "total":     fail_total,
            "rate":      fail_rate,
            "by_type":   by_type,
            "by_domain": by_domain,
        }

        # ═══ 4. Recent logs (phân trang) ═══
        total_logs  = base_query.count()
        total_pages = max(1, (total_logs + per_page - 1) // per_page)
        logs_page   = (
            base_query
            .order_by(Logs.request_time.desc())
            .offset((page - 1) * per_page)
            .limit(per_page)
            .all()
        )

        # Preload translation + file trong 1 query, tránh N+1
        translation_ids = [log.translation_id for log in logs_page if log.translation_id]
        file_ids        = [log.file_id        for log in logs_page if log.file_id]

        trans_map: dict[int, Translation] = {}
        if translation_ids:
            for t in db.query(Translation).filter(Translation.trans_id.in_(translation_ids)).all():
                trans_map[t.trans_id] = t

        file_map: dict[int, File] = {}
        if file_ids:
            for f in db.query(File).filter(File.file_id.in_(file_ids)).all():
                file_map[f.file_id] = f

        recent_logs = []
        for log in logs_page:
            entry = {
                "log_id":         log.log_id,
                "session_id":     log.session_id,
                "request_type":   log.request_type.value if log.request_type else "",
                "status":         log.status.value       if log.status        else "",
                "request_time":   log.request_time.isoformat() if log.request_time else "",
                "translation_id": log.translation_id,
                "file_id":        log.file_id,
                "model_name":     None,
                "domain_name":    None,
                "error_message":  None,
            }
            if log.translation_id:
                trans = trans_map.get(log.translation_id)
                if trans:
                    entry["model_name"]  = trans.model_name
                    entry["domain_name"] = domain_map.get(trans.domain_id)
            elif log.file_id:
                file = file_map.get(log.file_id)
                if file:
                    entry["domain_name"]   = domain_map.get(file.domain_id)
                    entry["error_message"] = file.error_message
            recent_logs.append(entry)

        # ═══ 5. Return ═══
        return {
            "stats":               stats,
            "domain_distribution": domain_distribution,
            "failed_stats":        failed_stats,
            "recent_logs":         recent_logs,
            "available_domains": [
                {"domain_id": d.domain_id, "domain_name": d.domain_name.value}
                for d in available_domains
            ],
            "available_models": [m[0] for m in available_models if m[0]],
            "log_pagination": {
                "total":        total_logs,
                "total_pages":  total_pages,
                "current_page": page,
            },
        }

    except Exception as e:
        logger.exception("Dashboard error")
        return {"detail": str(e)}
