# Consul — Service Discovery, Health Checks aur KV Store

A single-node **Consul** (dev agent) running in Docker on a Kali VM: a sample nginx web service is registered with an HTTP health check, configuration lives in Consul's **KV store**, the service is discovered by **name over Consul DNS** (`web.service.consul`) with no hard-coded IP, and — as a bonus — three KV values are managed from code with the **Terraform Consul provider**.

Publisher: **Zain Tech Automation Solutions** — Automate. Accelerate. Achieve.

## Status

**Complete — verified by an actual run** (see "Verified run" below), including a health-check failure-and-recovery cycle and DNS resolution of the service by name.

## Architecture

```
Browser -> Consul UI http://localhost:8500
Kali VM (Docker host)
  consul-server container (hashicorp/consul, dev agent)
    8500 UI/API · 8600 DNS · 8301 Serf LAN
  web1 container (nginx, host network, port 80)
    registered in Consul as "web" (web.service.consul)
    health check: HTTP GET every 10s
  KV store: config/web/* (6 keys — 3 by CLI, 3 by Terraform)
```

## Files

- `config/web-service.json` — the service registration (name, tags, address, port, HTTP health check) sent to `PUT /v1/agent/service/register`
- `index.html` — the sample web service page mounted into the nginx container
- `terraform/main.tf` — Terraform Consul provider + `consul_keys` resource managing 3 KV values

## Run it yourself

```bash
# 1. Consul dev agent
docker run -d --name consul-server -p 8500:8500 -p 8600:8600/udp -p 8600:8600/tcp -p 8301:8301 hashicorp/consul agent -dev -client=0.0.0.0 -ui
curl -s http://localhost:8500/v1/status/leader

# 2. Sample web service (host network, port 80)
docker run -d --name web1 --network host -v ~/consul-service-discovery/index.html:/usr/share/nginx/html/index.html:ro nginx

# 3. Register the service with its health check
curl -s -X PUT --data @config/web-service.json http://localhost:8500/v1/agent/service/register

# 4. KV store
docker exec consul-server consul kv put config/web/welcome "Zain Tech Automation Solutions me khush amdeed"
docker exec consul-server consul kv get -recurse config/

# 5. Discover the service by name over DNS
dig @127.0.0.1 -p 8600 web.service.consul

# 6. Bonus: manage KV from Terraform
cd terraform && terraform init && terraform apply
```

## Tech stack

Consul 2.1.0 (Docker image `hashicorp/consul`, dev agent) · Docker 28.5.2 · nginx · Terraform + hashicorp/consul provider (~> 2.20) · dig (dnsutils) · Kali Linux 2026.3

## Free / honesty note

Everything ran locally in Docker with the open-source Consul — completely free. **HCP Consul** (HashiCorp's cloud offering) is paid/trial and was **not** used; no account was created. Dev mode keeps data in memory only — the container stops, the data is gone; that is fine for learning and is **not** a production setup.

## What I learned

- **Service discovery:** services register by name; consumers look the name up (API or DNS) instead of hard-coding IPs that change.
- **Health checks:** Consul re-checks every few seconds; a failing service is marked critical and **disappears from DNS answers** until it recovers — traffic only reaches healthy instances.
- **KV store:** configuration (welcome text, limits, feature flags) can change centrally with no redeploy.
- **Terraform is not only for cloud:** the same IaC workflow manages Consul KV configuration via its provider.

## Challenges faced (and fixed)

- **Registration rejected — `Request decode failed: json: unknown field "ID"`.** Inside a service registration, the health check's ID field is named **`CheckID`**, not `ID`. Renaming that one field fixed the registration.
- **Check could never pass — DNS answered NXDOMAIN.** The health check pointed at `http://127.0.0.1:80/`, but the check runs *inside* the Consul container, where port 80 is empty — nginx runs on the host network. A service whose check never passes is hidden from DNS by design. Fix: point the check at the docker0 gateway address (`http://172.17.0.1:80/`), which the agent can reach; the check went passing and DNS immediately resolved the service.
- **Port 80 was already taken** by a host nginx from earlier projects — stopped it first (`systemctl stop nginx`) so the `web1` container could bind the port.

## Verified run

Environment: Kali Linux 2026.3 VM · Docker 28.5.2 · Consul 2.1.0 dev agent · Terraform with Consul provider

**Agent up, leader elected:**

```
$ curl -s http://localhost:8500/v1/status/leader
"127.0.0.1:8300"
$ curl -s http://localhost:8500/v1/catalog/services     # before registration
{ "consul": [] }
```

**Registration + health:** after fixing the `CheckID` field and the check target (see Challenges), the service registered and its aggregated health status became **passing**. Stopping `web1` flipped the status to **critical** within one check cycle; starting it again returned it to **passing**.

**KV store** (first 3 keys via CLI, last 3 via Terraform):

```
$ docker exec consul-server consul kv get -recurse config/
config/web/app_name:ZainTech Web Service
config/web/environment:home-lab
config/web/maintenance_mode:false
config/web/max_items:25
config/web/owner:Zain Tech Automation Solutions
config/web/welcome:Zain Tech Automation Solutions me khush amdeed
```

**DNS service discovery** — the name resolves to the service address with no IP known beforehand:

```
$ dig @127.0.0.1 -p 8600 web.service.consul
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 28421
;; QUESTION SECTION:
;web.service.consul.            IN      A
;; ANSWER SECTION:
web.service.consul.     0       IN      A       127.0.0.1
```

**Terraform bonus:**

```
$ terraform apply -auto-approve
consul_keys.web_config: Creation complete after 1s [id=consul]
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
$ docker exec consul-server consul kv get config/web/app_name
ZainTech Web Service
```
