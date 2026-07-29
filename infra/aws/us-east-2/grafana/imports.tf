import {
  to = grafana_data_source.cloudwatch
  id = "1:ffgmjtsy2uxogc"
}

import {
  to = grafana_data_source.prometheus
  id = "1:efgmimxclccn4a"
}

import {
  to = grafana_data_source.loki-gateway
  id = "1:efgmmv5m20wsgb"
}

import {
  to = grafana_data_source.postgres
  id = "1:cfgmmv670x4aoa"
}

import {
  to = grafana_dashboard.this["coder-dashboard-status"]
  id = "0:coder-status"
}

import {
  to = grafana_dashboard.this["coder-dashboard-coderd"]
  id = "0:coderd"
}

import {
  to = grafana_dashboard.this["coder-dashboard-provisionerd"]
  id = "0:provisionerd"
}

import {
  to = grafana_dashboard.this["coder-dashboard-workspaces"]
  id = "0:workspaces"
}

import {
  to = grafana_dashboard.this["coder-dashboard-workspace-detail"]
  id = "0:workspace-detail"
}

import {
  to = grafana_dashboard.this["coder-dashboard-prebuilds"]
  id = "0:cej6jysyme22oa"
}

import {
  to = grafana_dashboard.this["coder-dashboard-aibridge"]
  id = "0:0c61d33f-c809-4184-9e88-cb27e2d9d224"
}

import {
  to = grafana_dashboard.this["coder-dashboard-boundary"]
  id = "0:agent-boundaries"
}

import {
  to = grafana_organization_preferences.this
  id = "0"
}