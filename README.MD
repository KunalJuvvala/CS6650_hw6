# Product API — Gin + Docker + Terraform (ECS) + Locust + Prometheus/Grafana

A small Product service implementing the Product endpoints of `api.yaml`, deployed to AWS ECS (Fargate) with Terraform, load tested with Locust, and observed with Prometheus + Grafana and structured JSON logs.

## Where things are

| Path | What it is |
|---|---|
| `src/product-service.go` | Server code (Gin handlers, in-memory store, metrics, logging) |
| `src/Dockerfile` | Multi-stage build of the server image |
| `src/go.mod`, `src/go.sum` | Go module + dependency lock |
| `terraform/` | Infrastructure as code (`provider.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `modules/`) |
| `locust/locustfile.py` | Load tests (`ProductHttpUser` and `ProductFastUser`) |
| `monitoring/` | docker-compose for app + Prometheus + Grafana, with a pre-built RED dashboard |
| `screenshots/` | Locust, Grafana and request screenshots |

## API

| Method | Path | Responses |
|---|---|---|
| GET | `/products/{productId}` | 200 Product, 404 not found, 500 internal error |
| POST | `/products/{productId}/details` | 204 updated, 400 invalid input, 404 not found, 500 internal error |
| GET | `/metrics` | Prometheus metrics |
| GET | `/health` | Liveness check |

Products with IDs `1..100` are pre-loaded at startup (`SEED_PRODUCTS` env var). Storage is an in-memory `map[int]Product` guarded by a `sync.RWMutex`.

## Run locally

```bash
cd src
go run .                                   # listens on :8080
# or with Docker
docker build -t product-service .
docker run --rm -p 8080:8080 -e ENABLE_FAULT_INJECTION=true product-service
```

## Examples for every response code

Set the base URL first: `BASE=http://localhost:8080` (or `http://<ECS_PUBLIC_IP>:8080`).

**GET 200**
```bash
curl -i $BASE/products/1
```
**GET 404** (product does not exist)
```bash
curl -i $BASE/products/99999
```
**GET 500** (requires `ENABLE_FAULT_INJECTION=true` on the server)
```bash
curl -i -H "X-Fault-Inject: 500" $BASE/products/1
```
**POST 204**
```bash
curl -i -X POST $BASE/products/1/details -H "Content-Type: application/json" \
  -d '{"product_id":1,"sku":"ABC-123","manufacturer":"Acme","category_id":5,"weight":250,"some_other_id":42}'
```
**POST 400** (missing field / body id does not match path / malformed JSON)
```bash
curl -i -X POST $BASE/products/1/details -H "Content-Type: application/json" \
  -d '{"product_id":1,"manufacturer":"Acme","category_id":5,"weight":250,"some_other_id":42}'
curl -i -X POST $BASE/products/1/details -H "Content-Type: application/json" \
  -d '{"product_id":2,"sku":"ABC-123","manufacturer":"Acme","category_id":5,"weight":250,"some_other_id":42}'
curl -i -X POST $BASE/products/1/details -H "Content-Type: application/json" -d '{bad json'
# number too large for int32 (format: int32 in api.yaml)
curl -i -X POST $BASE/products/1/details -H "Content-Type: application/json" \
  -d '{"product_id":1,"sku":"ABC-123","manufacturer":"Acme","category_id":5,"weight":3000000000,"some_other_id":42}'
```
**POST 404** (valid body, product does not exist)
```bash
curl -i -X POST $BASE/products/99999/details -H "Content-Type: application/json" \
  -d '{"product_id":99999,"sku":"ABC-123","manufacturer":"Acme","category_id":5,"weight":250,"some_other_id":42}'
```
**POST 500** (requires `ENABLE_FAULT_INJECTION=true`)
```bash
curl -i -X POST -H "X-Fault-Inject: 500" $BASE/products/1/details -H "Content-Type: application/json" -d '{}'
```

Screenshots: `screenshots/responses/` <!-- add your images here -->

## Deploy on any machine (AWS Learner Lab)

**Prerequisites:** Docker (running), Terraform ≥ 1.5, AWS CLI v2, Git.

1. Start the Learner Lab, open **AWS Details → AWS CLI → Show**, and paste the block into `~/.aws/credentials` (it expires every few hours; repeat this when you see `ExpiredToken`).
2. Clone and deploy:
   ```bash
   git clone <this-repo-url>
   cd <repo>/terraform
   terraform init
   terraform apply        # type "yes"
   ```
   Terraform builds the image from `src/`, pushes it to ECR, and starts it on ECS.
3. Get the public IP of the running task (replace the region if `variables.tf` uses a different one):
   ```bash
   REGION=us-west-2
   CLUSTER=$(terraform output -raw ecs_cluster_name)
   SERVICE=$(terraform output -raw ecs_service_name)
   TASK=$(aws ecs list-tasks --cluster $CLUSTER --service-name $SERVICE --region $REGION --query 'taskArns[0]' --output text)
   ENI=$(aws ecs describe-tasks --cluster $CLUSTER --tasks $TASK --region $REGION \
         --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" --output text)
   aws ec2 describe-network-interfaces --network-interface-ids $ENI --region $REGION \
         --query 'NetworkInterfaces[0].Association.PublicIp' --output text
   ```
4. Test: `curl -i http://<PUBLIC_IP>:8080/products/1`
5. Tear down when done: `terraform destroy`

## Load testing (Part IV)

<!-- Describe your test design, results and screenshots here -->

```bash
pip install locust
locust -f locust/locustfile.py ProductFastUser --host http://<PUBLIC_IP>:8080   # UI at http://localhost:8089
```

- Test design: …
- Breaking point: …
- HttpUser vs FastHttpUser: …
- Screenshots: `screenshots/locust/`

## Observability (Part V)

```bash
cd monitoring
docker compose up --build      # Grafana: http://localhost:3000, Prometheus: http://localhost:9090
```

- Dashboard (idle vs loaded): `screenshots/grafana/`
- Log excerpt from the same run:
```json
<!-- paste 5–10 lines here -->
```
- Dashboard vs logs: …
