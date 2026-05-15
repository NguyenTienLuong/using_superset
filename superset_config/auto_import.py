import time, os, subprocess

EXPORT_FILE = "/app/superset_home/dashboard_export_20260514T151310.zip"
FLAG_FILE = "/app/superset_home/imported.flag"

def main():
    time.sleep(30)
    if os.path.exists(FLAG_FILE):
        print(">>> Đã import trước đó, bỏ qua.")
        return
    if not os.path.exists(EXPORT_FILE):
        print(">>> Không tìm thấy file export dashboard.")
        return

    print(">>> Đang import dashboard...")
    result = subprocess.run(
        ["superset", "import-dashboard", "--path", EXPORT_FILE],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(">>> Lỗi import:", result.stderr)
        return
    print(result.stdout)

if __name__ == "__main__":
    main()