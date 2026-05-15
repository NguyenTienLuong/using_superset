import time, os, subprocess
from superset import create_app

app = create_app()
app.app_context().push()

from superset.extensions import db
from superset.models.dashboard import Dashboard
from superset.models.core import Role

EXPORT_FILE = "/app/superset_home/dashboard_export_20260514T151310.zip"
FLAG_FILE = "/app/superset_home/imported.flag"
SLUG = "drupal"

def main():
    time.sleep(30)  # Đợi Superset sẵn sàng

    if os.path.exists(FLAG_FILE):
        print(">>> Đã import trước đó, bỏ qua.")
        return

    if not os.path.exists(EXPORT_FILE):
        print(">>> Không tìm thấy file export dashboard.")
        return

    # Import dashboard bằng lệnh CLI
    print(">>> Đang import dashboard...")
    result = subprocess.run(
        ["superset", "import-dashboard", "--path", EXPORT_FILE],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(">>> Lỗi import:", result.stderr)
        return
    print(result.stdout)

    # Gán quyền Public
    dashboard = db.session.query(Dashboard).filter_by(slug=SLUG).first()
    if not dashboard:
        print(f">>> Không tìm thấy dashboard có slug '{SLUG}'.")
        return

    public_role = db.session.query(Role).filter_by(name='Public').first()
    if not public_role:
        public_role = Role(name='Public')
        db.session.add(public_role)
        db.session.flush()

    if public_role not in dashboard.roles:
        dashboard.roles.append(public_role)
        db.session.commit()
        print(">>> Đã gán quyền Public cho dashboard.")
    else:
        print(">>> Quyền Public đã tồn tại.")

    with open(FLAG_FILE, 'w') as f:
        f.write('1')
    print(">>> Hoàn tất auto_import.")

if __name__ == "__main__":
    main()