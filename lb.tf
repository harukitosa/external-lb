/**
 * Copyright 2020 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

provider "google" {
  project = var.project_id
}

provider "google-beta" {
  project = var.project_id
}

# Variables

variable "project_id" {
  description = "the project to deploy the resources"
  type        = string
}

variable "name" {
  description = "the name prefix for load balancer resources"
  type        = string
}

variable "region" {
  description = "The region of the backend."
  type        = string
}

variable "cloud_run_service" {
  description = "The name of the Cloud Run service."
  type        = string
}

variable "cloud_run_service2" {
  description = "The name of the Cloud Run service."
  type        = string
}

variable "keys" {
  type        = list(string)
  description = "list of change service api-key"
  default     = []
}

# default
resource "google_cloud_run_service" "default" {
  name     = var.cloud_run_service
  location = var.region
  project  = var.project_id

  template {
    spec {
      containers {
        image = "gcr.io/cloudrun/hello"
      }
    }
  }
}

# default2
resource "google_cloud_run_service" "default2" {
  name     = var.cloud_run_service2
  location = var.region
  project  = var.project_id

  template {
    spec {
      containers {
        image = "gcr.io/cloudrun/hello"
      }
    }
  }
}

resource "google_cloud_run_service_iam_member" "member" {
  location = google_cloud_run_service.default.location
  project  = google_cloud_run_service.default.project
  service  = google_cloud_run_service.default.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# default2
resource "google_cloud_run_service_iam_member" "member2" {
  location = google_cloud_run_service.default2.location
  project  = google_cloud_run_service.default2.project
  service  = google_cloud_run_service.default2.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Load Balancing resources

resource "google_compute_global_address" "default" {
  name = "${var.name}-address"
}

resource "google_compute_global_forwarding_rule" "default" {
  name = "${var.name}-fwdrule"

  target     = google_compute_target_http_proxy.default.id
  port_range = "80"
  ip_address = google_compute_global_address.default.address
}

resource "google_compute_backend_service" "default" {
  name = "${var.name}-backend"

  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 30

  backend {
    group = google_compute_region_network_endpoint_group.cloudrun_neg.id
  }
}

resource "google_compute_backend_service" "default2" {
  name = "${var.name}-backend2"

  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 30

  backend {
    group = google_compute_region_network_endpoint_group.cloudrun_neg2.id
  }
}

resource "google_compute_url_map" "default" {
  name            = "${var.name}-urlmap"
  default_service = google_compute_backend_service.default.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "default"
  }

  path_matcher {
    name            = "default"
    default_service = google_compute_backend_service.default.self_link

    dynamic "route_rules" {
      for_each = var.keys
      content {
        priority = 1 + index(var.keys, route_rules.value) 
        service  = google_compute_backend_service.default2.id
        match_rules {
          header_matches {
            header_name = "X-ABTEST"
            exact_match = route_rules.value
          }
        }
      }
    }

    route_rules {
      priority = 1 + length(var.keys)
      service = google_compute_backend_service.default2.id
      match_rules {
        prefix_match = "/default2"
      }
    }
  }
}

resource "google_compute_target_http_proxy" "default" {
  name    = "${var.name}-http-proxy"
  url_map = google_compute_url_map.default.id
}

resource "google_compute_region_network_endpoint_group" "cloudrun_neg" {
  provider              = google-beta
  name                  = "${var.name}-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  cloud_run {
    service = google_cloud_run_service.default.name
  }
}

resource "google_compute_region_network_endpoint_group" "cloudrun_neg2" {
  provider              = google-beta
  name                  = "${var.name}-neg2"
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  cloud_run {
    service = google_cloud_run_service.default2.name
  }
}

resource "google_compute_url_map" "https_redirect" {
  name = "${var.name}-https-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# Outputs
output "cloud_run_url" {
  value = element(google_cloud_run_service.default.status, 0).url
}

output "load_balancer_ip" {
  value = google_compute_global_address.default.address
}