# Build emailservice (python)
deactivate 2>/dev/null || true # leave the current venv
cd ~/microservices-demo/src/emailservice
python3 -m venv venv
source venv/bin/activate
python -m pip install --upgrade pip setuptools wheel

# 2) install ONLY emailservice deps in THIS venv
pip install -r requirements.txt
pip install pyinstaller

# 3) (optional) build a single-file binary with PyInstaller
#    First, confirm the entrypoint file (one of these usually exists):
#      - email_server.py   -or-   server.py
#    Check quickly:
ls | egrep 'email_?server\.py|server\.py' || true

# Example if entrypoint is email_server.py:
pyinstaller --onefile email_server.py --name emailservice
mv dist/emailservice ../../bin/emailservice

# Build recommendationservice (python)
deactivate 2>/dev/null || true # leave the current venv
cd ~/microservices-demo/src/recommendationservice
python3 -m venv venv
source venv/bin/activate
python -m pip install --upgrade pip setuptools wheel

# 2) install ONLY recommendationservice deps in THIS venv
pip install -r requirements.txt
pip install pyinstaller


# 3) (optional) build a single-file binary with PyInstaller
#    First, confirm the entrypoint file (one of these usually exists):
#      - email_server.py   -or-   server.py
#    Check quickly:
ls | egrep 'recommendation_?server\.py|server\.py' || true

# Example if entrypoint is recommendation_server.py:
pyinstaller --onefile recommendation_server.py --name recommendationservice
mv dist/recommendationservice ../../bin/recommendationservice
