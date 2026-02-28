.PHONY: install tf-init tf-plan tf-apply tf-destroy ingest run-glue run-pipeline dashboard

install:
	python3 -m venv .venv
	.venv/bin/pip install -r requirements.txt

# Terraform (infra/)
tf-init:
	cd infra && terraform init

tf-plan:
	cd infra && terraform plan

tf-apply:
	cd infra && terraform apply -auto-approve

tf-destroy:
	cd infra && terraform destroy -auto-approve

# Ingestion (requires DATA_BUCKET from terraform output)
ingest:
	.venv/bin/python scripts/ingest_mrts.py --ingest-date $$(date +%Y-%m-%d)

# Glue ETL (run via AWS CLI)
run-glue:
	aws glue start-job-run --job-name $$(cd infra && terraform output -raw glue_job_name)

# Full pipeline via Step Functions
run-pipeline:
	aws stepfunctions start-execution \
	  --state-machine-arn $$(cd infra && terraform output -raw state_machine_arn)

# Dashboard
dashboard:
	cd dashboard && pip install -r requirements.txt && streamlit run app.py
