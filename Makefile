.PHONY: deploy upload run crawler dashboard setup-env destroy

deploy:
	cd infrastructure/terraform && terraform init && terraform apply -auto-approve

setup-env:
	bash scripts/setup_env.sh

upload:
	bash scripts/upload_sample_data.sh

run:
	bash scripts/run_pipeline.sh

crawler:
	bash scripts/run_crawler.sh

dashboard:
	pip install -q -r dashboard/requirements.txt && cd dashboard && STREAMLIT_SERVER_HEADLESS=true STREAMLIT_BROWSER_GATHER_USAGE_STATS=false python -m streamlit run app.py

destroy:
	cd infrastructure/terraform && terraform destroy -auto-approve
