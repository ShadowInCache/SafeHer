# Makefile for SafeHer
#
# Targets that referenced scripts/setup.py, scripts/train_all.py and
# scripts/test_apis.py were removed on 2026-08-15 -- none of those files have
# ever existed in this repo, so `make setup`, `make train` and `make test` all
# failed on a fresh clone.

.PHONY: help backend backend-stop install test test-backend test-mobile \
        analyze clean flutter-setup flutter-run flutter-web flutter-build \
        migrate migrate-status doctor

help:
	@echo "SafeHer"
	@echo "======="
	@echo ""
	@echo "Run"
	@echo "  make backend        - Start the FastAPI backend on :5000 (the app needs this)"
	@echo "  make backend-stop   - Stop whatever is listening on :5000"
	@echo "  make flutter-web    - Run the app in Chrome"
	@echo "  make flutter-run    - Run the app on a connected device"
	@echo ""
	@echo "Verify"
	@echo "  make doctor         - Is the backend up? Which platforms are configured?"
	@echo "  make test           - Backend + mobile test suites"
	@echo "  make analyze        - flutter analyze"
	@echo ""
	@echo "Database"
	@echo "  make migrate        - Apply migrations (alembic upgrade head)"
	@echo "  make migrate-status - Show the current revision"
	@echo ""
	@echo "Misc"
	@echo "  make install        - pip install -r requirements.txt"
	@echo "  make flutter-setup  - flutter pub get"
	@echo "  make flutter-build  - Release APK"
	@echo "  make clean          - Remove caches and build artifacts"

# --------------------------------------------------------------------- run

# The mobile app talks to http://127.0.0.1:5000/api/v1 by default. Without this
# running, sign-in fails with "Cannot reach SafeHer" -- which looks like an app
# bug but is just a missing backend.
backend:
	python -m uvicorn fastapi_app.main:app --host 127.0.0.1 --port 5000 --reload

backend-stop:
	@echo "Stopping anything on :5000..."
	@netstat -ano | grep ':5000' | grep LISTENING | awk '{print $$5}' | sort -u | \
		xargs -r -I{} taskkill //PID {} //F 2>/dev/null || echo "  nothing was listening"

flutter-run:
	cd mobile && flutter run

flutter-web:
	cd mobile && flutter run -d chrome

# ------------------------------------------------------------------ verify

doctor:
	@echo "Backend (:5000):"
	@curl -s -o /dev/null -w "  health -> HTTP %{http_code}\n" --max-time 5 \
		http://127.0.0.1:5000/api/v1/health || echo "  DOWN - run 'make backend'"
	@echo "Firebase platform config:"
	@python -c "import json; d=json.load(open('mobile/android/app/google-services.json')); \
t=[e.get('client_type') for e in d['client'][0].get('oauth_client',[])]; \
print('  android: Google sign-in', 'READY' if 1 in t else 'BLOCKED (SHA-1 not registered)')"
	@python -c "import os; print('  ios    : config', 'present' if os.path.exists('mobile/ios/Runner/GoogleService-Info.plist') else 'MISSING')"

# Skips test_api_gateway.py and test_integration.py: those drive a live server
# over HTTP rather than the ASGI app, so they need `make backend` running first.
test-backend:
	python -m pytest tests/ -q --ignore=tests/test_api_gateway.py --ignore=tests/test_integration.py

test-mobile:
	cd mobile && flutter test

test: test-backend test-mobile

analyze:
	cd mobile && flutter analyze

# ---------------------------------------------------------------- database

# `python -m alembic`, not bare `alembic`: the console script can resolve to a
# different interpreter than the one running the backend.
migrate:
	python -m alembic upgrade head

migrate-status:
	python -m alembic current

# -------------------------------------------------------------------- misc

install:
	pip install -r requirements.txt

flutter-setup:
	cd mobile && flutter pub get

flutter-build:
	cd mobile && flutter build apk --release

clean:
	find . -type d -name __pycache__ -not -path './.venv/*' -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -not -path './.venv/*' -delete 2>/dev/null || true
	rm -rf .pytest_cache 2>/dev/null || true
	cd mobile && flutter clean
