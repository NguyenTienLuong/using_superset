-- ============================================================
-- Init script for Translation Dashboard Testing
-- Period: Jan-May 2026, 5 requests/month (4 text + 1 file)
-- Language: English → Vietnamese only
-- ============================================================

DO $$ BEGIN CREATE TYPE domain_name_t AS ENUM ('general', 'business', 'technical', 'medical'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE status_t AS ENUM ('pending', 'success', 'error'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE file_type_t AS ENUM ('pdf', 'docx', 'txt'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE request_type_t AS ENUM ('text', 'file'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS language (
    lang_id SERIAL PRIMARY KEY,
    lang_code VARCHAR(10) UNIQUE NOT NULL,
    lang_name VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS domain (
    domain_id SERIAL PRIMARY KEY,
    domain_name domain_name_t NOT NULL DEFAULT 'general'
);

CREATE TABLE IF NOT EXISTS session (
    session_id VARCHAR(64) PRIMARY KEY,
    ip_address VARCHAR(50),
    user_agent TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS translation (
    trans_id BIGSERIAL PRIMARY KEY,
    source_text TEXT NOT NULL,
    translated_text TEXT NOT NULL,
    text_hash CHAR(64) NOT NULL,
    source_lang INTEGER NOT NULL REFERENCES language(lang_id),
    target_lang INTEGER NOT NULL REFERENCES language(lang_id),
    domain_id INTEGER NOT NULL REFERENCES domain(domain_id),
    model_name VARCHAR(100) NOT NULL,
    temperature FLOAT,
    token_usage INTEGER,
    session_id VARCHAR(64) REFERENCES session(session_id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT uniq_translation_cache UNIQUE (text_hash, source_lang, target_lang, domain_id)
);

CREATE TABLE IF NOT EXISTS file (
    file_id BIGSERIAL PRIMARY KEY,
    original_filename VARCHAR(255),
    translated_filename VARCHAR(255),
    file_path TEXT,
    file_size INTEGER,
    source_lang INTEGER REFERENCES language(lang_id),
    target_lang INTEGER REFERENCES language(lang_id),
    domain_id INTEGER REFERENCES domain(domain_id),
    session_id VARCHAR(64) REFERENCES session(session_id) ON DELETE CASCADE,
    uploaded_at TIMESTAMP NOT NULL DEFAULT NOW(),
    file_type file_type_t,
    status status_t NOT NULL DEFAULT 'pending',
    error_message TEXT
);

CREATE TABLE IF NOT EXISTS file_segment (
    segment_id BIGSERIAL PRIMARY KEY,
    file_id BIGINT REFERENCES file(file_id) ON DELETE CASCADE,
    source_text TEXT,
    translated_text TEXT,
    text_hash CHAR(64),
    segment_order INTEGER
);

CREATE TABLE IF NOT EXISTS logs (
    log_id BIGSERIAL PRIMARY KEY,
    session_id VARCHAR(64) REFERENCES session(session_id) ON DELETE CASCADE,
    request_type request_type_t,
    translation_id BIGINT REFERENCES translation(trans_id) ON DELETE CASCADE,
    file_id BIGINT REFERENCES file(file_id) ON DELETE CASCADE,
    status status_t,
    request_time TIMESTAMP,
    completed_time TIMESTAMP,
    ip_address VARCHAR(50)
);

CREATE INDEX IF NOT EXISTS idx_translation_lang ON translation (source_lang, target_lang);
CREATE INDEX IF NOT EXISTS idx_translation_domain ON translation (domain_id);
CREATE INDEX IF NOT EXISTS idx_file_segment_file ON file_segment (file_id);
CREATE INDEX IF NOT EXISTS idx_logs_time ON logs (request_time);
CREATE INDEX IF NOT EXISTS idx_logs_session ON logs (session_id);

-- ============================================================
-- Seed data
-- ============================================================

-- Languages
INSERT INTO language (lang_code, lang_name) VALUES ('vi', 'Vietnamese');
INSERT INTO language (lang_code, lang_name) VALUES ('en', 'English');

-- Domains
INSERT INTO domain (domain_name) VALUES ('general'), ('business'), ('technical'), ('medical');

-- Sessions (5 fixed)
INSERT INTO session (session_id, ip_address, user_agent) VALUES
('sess-001','10.0.0.1','Mozilla/5.0 (Test)'),
('sess-002','10.0.0.2','Mozilla/5.0 (Test)'),
('sess-003','10.0.0.3','Mozilla/5.0 (Test)'),
('sess-004','10.0.0.4','Mozilla/5.0 (Test)'),
('sess-005','10.0.0.5','Mozilla/5.0 (Test)');

-- Helper function to avoid repeat
-- We'll insert translations and logs for each month directly.

-- ============================================================
-- Jan 2026: 4 text + 1 file
-- ============================================================
INSERT INTO translation (source_text, translated_text, text_hash, source_lang, target_lang, domain_id, model_name, temperature, token_usage, session_id, created_at)
VALUES
 ('Hello world', 'Xin chào thế giới', MD5('src1'), 2, 1, 1, 'gpt-4o', 0.7, 12, 'sess-001', '2026-01-15 10:00:00'),
 ('Good morning', 'Chào buổi sáng', MD5('src2'), 2, 1, 2, 'claude-3-5-sonnet', 0.5, 8, 'sess-002', '2026-01-15 11:00:00'),
 ('Thank you', 'Cảm ơn', MD5('src3'), 2, 1, 3, 'gpt-3.5-turbo', 0.3, 5, 'sess-003', '2026-01-15 12:00:00'),
 ('How are you?', 'Bạn khỏe không?', MD5('src4'), 2, 1, 4, 'claude-3-haiku', 0.6, 9, 'sess-004', '2026-01-15 13:00:00');

INSERT INTO file (original_filename, file_path, file_size, source_lang, target_lang, domain_id, session_id, uploaded_at, file_type, status)
VALUES ('report_jan.pdf','/uploads/jan.pdf', 102400, 2, 1, 1, 'sess-005', '2026-01-20 09:00:00', 'pdf', 'success');

INSERT INTO file_segment (file_id, source_text, translated_text, text_hash, segment_order)
VALUES (1, 'Segment 1', 'Phân đoạn 1', MD5('f1s1'), 1),
       (1, 'Segment 2', 'Phân đoạn 2', MD5('f1s2'), 2);

INSERT INTO logs (session_id, request_type, translation_id, file_id, status, request_time, completed_time, ip_address) VALUES
('sess-001','text',1,NULL,'success','2026-01-15 10:00:00','2026-01-15 10:00:02','10.0.0.1'),
('sess-002','text',2,NULL,'success','2026-01-15 11:00:00','2026-01-15 11:00:01','10.0.0.2'),
('sess-003','text',3,NULL,'error','2026-01-15 12:00:00',NULL,'10.0.0.3'),
('sess-004','text',4,NULL,'success','2026-01-15 13:00:00','2026-01-15 13:00:03','10.0.0.4'),
('sess-005','file',NULL,1,'success','2026-01-20 09:00:00','2026-01-20 09:00:05','10.0.0.5');

-- ============================================================
-- Feb 2026
-- ============================================================
INSERT INTO translation (source_text, translated_text, text_hash, source_lang, target_lang, domain_id, model_name, temperature, token_usage, session_id, created_at)
VALUES
 ('Good evening', 'Chào buổi tối', MD5('src5'), 2, 1, 2, 'gpt-4o', 0.8, 15, 'sess-002', '2026-02-15 10:00:00'),
 ('See you later', 'Hẹn gặp lại', MD5('src6'), 2, 1, 1, 'claude-3-5-sonnet', 0.4, 7, 'sess-003', '2026-02-15 11:00:00'),
 ('Nice to meet you', 'Rất vui được gặp', MD5('src7'), 2, 1, 4, 'gpt-3.5-turbo', 0.6, 11, 'sess-001', '2026-02-15 12:00:00'),
 ('What is your name?', 'Tên bạn là gì?', MD5('src8'), 2, 1, 3, 'claude-3-haiku', 0.5, 8, 'sess-004', '2026-02-15 13:00:00');

INSERT INTO file (original_filename, file_path, file_size, source_lang, target_lang, domain_id, session_id, uploaded_at, file_type, status)
VALUES ('invoice_feb.pdf','/uploads/feb.pdf', 204800, 2, 1, 2, 'sess-001', '2026-02-20 09:00:00', 'pdf', 'success');

INSERT INTO file_segment (file_id, source_text, translated_text, text_hash, segment_order)
VALUES (2, 'Invoice line 1', 'Dòng hóa đơn 1', MD5('f2s1'), 1);

INSERT INTO logs (session_id, request_type, translation_id, file_id, status, request_time, completed_time, ip_address) VALUES
('sess-002','text',5,NULL,'success','2026-02-15 10:00:00','2026-02-15 10:00:02','10.0.0.2'),
('sess-003','text',6,NULL,'success','2026-02-15 11:00:00','2026-02-15 11:00:01','10.0.0.3'),
('sess-001','text',7,NULL,'pending','2026-02-15 12:00:00',NULL,'10.0.0.1'),
('sess-004','text',8,NULL,'success','2026-02-15 13:00:00','2026-02-15 13:00:03','10.0.0.4'),
('sess-001','file',NULL,2,'success','2026-02-20 09:00:00','2026-02-20 09:00:05','10.0.0.1');

-- ============================================================
-- Mar 2026
-- ============================================================
INSERT INTO translation (source_text, translated_text, text_hash, source_lang, target_lang, domain_id, model_name, temperature, token_usage, session_id, created_at)
VALUES
 ('I love programming', 'Tôi thích lập trình', MD5('src9'), 2, 1, 3, 'gpt-4o', 0.9, 20, 'sess-005', '2026-03-15 10:00:00'),
 ('This is a test', 'Đây là một bài kiểm tra', MD5('src10'), 2, 1, 1, 'claude-3-5-sonnet', 0.7, 13, 'sess-001', '2026-03-15 11:00:00'),
 ('Machine learning', 'Học máy', MD5('src11'), 2, 1, 4, 'gpt-3.5-turbo', 0.4, 9, 'sess-003', '2026-03-15 12:00:00'),
 ('Deep learning', 'Học sâu', MD5('src12'), 2, 1, 2, 'claude-3-haiku', 0.3, 6, 'sess-002', '2026-03-15 13:00:00');

INSERT INTO file (original_filename, file_path, file_size, source_lang, target_lang, domain_id, session_id, uploaded_at, file_type, status, error_message)
VALUES ('error_mar.pdf','/uploads/mar.pdf', 50000, 2, 1, 3, 'sess-003', '2026-03-20 09:00:00', 'docx', 'error', 'Format not supported');

INSERT INTO file_segment (file_id, source_text, translated_text, text_hash, segment_order)
VALUES (3, 'Error doc', NULL, MD5('f3s1'), 1);

INSERT INTO logs (session_id, request_type, translation_id, file_id, status, request_time, completed_time, ip_address) VALUES
('sess-005','text',9,NULL,'success','2026-03-15 10:00:00','2026-03-15 10:00:02','10.0.0.5'),
('sess-001','text',10,NULL,'success','2026-03-15 11:00:00','2026-03-15 11:00:01','10.0.0.1'),
('sess-003','text',11,NULL,'error','2026-03-15 12:00:00',NULL,'10.0.0.3'),
('sess-002','text',12,NULL,'success','2026-03-15 13:00:00','2026-03-15 13:00:03','10.0.0.2'),
('sess-003','file',NULL,3,'error','2026-03-20 09:00:00',NULL,'10.0.0.3');

-- ============================================================
-- Apr 2026
-- ============================================================
INSERT INTO translation (source_text, translated_text, text_hash, source_lang, target_lang, domain_id, model_name, temperature, token_usage, session_id, created_at)
VALUES
 ('Data science', 'Khoa học dữ liệu', MD5('src13'), 2, 1, 4, 'gpt-4o', 0.5, 16, 'sess-001', '2026-04-15 10:00:00'),
 ('Artificial intelligence', 'Trí tuệ nhân tạo', MD5('src14'), 2, 1, 2, 'claude-3-5-sonnet', 0.8, 22, 'sess-003', '2026-04-15 11:00:00'),
 ('Natural language processing', 'Xử lý ngôn ngữ tự nhiên', MD5('src15'), 2, 1, 1, 'gpt-3.5-turbo', 0.6, 14, 'sess-005', '2026-04-15 12:00:00'),
 ('Computer vision', 'Thị giác máy tính', MD5('src16'), 2, 1, 3, 'claude-3-haiku', 0.4, 10, 'sess-002', '2026-04-15 13:00:00');

INSERT INTO file (original_filename, file_path, file_size, source_lang, target_lang, domain_id, session_id, uploaded_at, file_type, status)
VALUES ('manual_apr.pdf','/uploads/apr.pdf', 307200, 2, 1, 4, 'sess-004', '2026-04-20 09:00:00', 'pdf', 'success');

INSERT INTO file_segment (file_id, source_text, translated_text, text_hash, segment_order)
VALUES (4, 'Introduction', 'Giới thiệu', MD5('f4s1'), 1),
       (4, 'Chapter 1', 'Chương 1', MD5('f4s2'), 2);

INSERT INTO logs (session_id, request_type, translation_id, file_id, status, request_time, completed_time, ip_address) VALUES
('sess-001','text',13,NULL,'success','2026-04-15 10:00:00','2026-04-15 10:00:02','10.0.0.1'),
('sess-003','text',14,NULL,'success','2026-04-15 11:00:00','2026-04-15 11:00:01','10.0.0.3'),
('sess-005','text',15,NULL,'pending','2026-04-15 12:00:00',NULL,'10.0.0.5'),
('sess-002','text',16,NULL,'success','2026-04-15 13:00:00','2026-04-15 13:00:03','10.0.0.2'),
('sess-004','file',NULL,4,'success','2026-04-20 09:00:00','2026-04-20 09:00:05','10.0.0.4');

-- ============================================================
-- May 2026
-- ============================================================
INSERT INTO translation (source_text, translated_text, text_hash, source_lang, target_lang, domain_id, model_name, temperature, token_usage, session_id, created_at)
VALUES
 ('Reinforcement learning', 'Học tăng cường', MD5('src17'), 2, 1, 3, 'gpt-4o', 0.7, 18, 'sess-003', '2026-05-15 10:00:00'),
 ('Generative adversarial network', 'Mạng đối kháng tạo sinh', MD5('src18'), 2, 1, 4, 'claude-3-5-sonnet', 0.5, 25, 'sess-005', '2026-05-15 11:00:00'),
 ('Transformer architecture', 'Kiến trúc Transformer', MD5('src19'), 2, 1, 2, 'gpt-3.5-turbo', 0.3, 12, 'sess-001', '2026-05-15 12:00:00'),
 ('Neural network', 'Mạng nơ-ron', MD5('src20'), 2, 1, 1, 'claude-3-haiku', 0.9, 7, 'sess-002', '2026-05-15 13:00:00');

INSERT INTO file (original_filename, file_path, file_size, source_lang, target_lang, domain_id, session_id, uploaded_at, file_type, status)
VALUES ('diagram_may.pdf','/uploads/may.pdf', 409600, 2, 1, 1, 'sess-003', '2026-05-20 09:00:00', 'pdf', 'success');

INSERT INTO file_segment (file_id, source_text, translated_text, text_hash, segment_order)
VALUES (5, 'Flowchart', 'Sơ đồ', MD5('f5s1'), 1);

INSERT INTO logs (session_id, request_type, translation_id, file_id, status, request_time, completed_time, ip_address) VALUES
('sess-003','text',17,NULL,'success','2026-05-15 10:00:00','2026-05-15 10:00:02','10.0.0.3'),
('sess-005','text',18,NULL,'success','2026-05-15 11:00:00','2026-05-15 11:00:01','10.0.0.5'),
('sess-001','text',19,NULL,'error','2026-05-15 12:00:00',NULL,'10.0.0.1'),
('sess-002','text',20,NULL,'success','2026-05-15 13:00:00','2026-05-15 13:00:03','10.0.0.2'),
('sess-003','file',NULL,5,'success','2026-05-20 09:00:00','2026-05-20 09:00:05','10.0.0.3');