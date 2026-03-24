.PHONY: deploy upload run crawler dashboard verify generate-data setup-env destroy

deploy:
	cd infrastructure/terraform && terraform init && terraform apply -auto-approve

setup-env:
	bash scripts/setup_env.sh

generate-data:
	python3 scripts/generate_sample_data.py -n 300

upload:
	bash scripts/upload_sample_data.sh

run:
	bash scripts/run_pipeline.sh

crawler:
	bash scripts/run_crawler.sh

verify:
	bash scripts/verify_pipeline.sh

dashboard:
	python -m pip install -q -r dashboard/requirements.txt && cd dashboard && STREAMLIT_SERVER_HEADLESS=true STREAMLIT_BROWSER_GATHER_USAGE_STATS=false python -m streamlit run app.py

destroy:
	bash scripts/destroy_prep.sh
	cd infrastructure/terraform && terraform destroy -auto-approve
