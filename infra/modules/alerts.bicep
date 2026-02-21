@description('Name prefix for alert resources')
param namePrefix string

@description('Web App resource ID')
param webAppId string

@description('Log Analytics workspace ID')
param logAnalyticsWorkspaceId string

@description('Email address for alert notifications')
param alertEmailAddress string = ''

@description('Tags for alert resources')
param tags object = {}

// --- Action Group ---
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (!empty(alertEmailAddress)) {
  name: '${namePrefix}-alerts-ag'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'OpenClawAG'
    enabled: true
    emailReceivers: [
      {
        name: 'AdminEmail'
        emailAddress: alertEmailAddress
      }
    ]
  }
}

var actionGroupId = !empty(alertEmailAddress) ? [
  {
    actionGroupId: actionGroup.id
  }
] : []

// --- Alert: High HTTP 5xx Error Rate ---
resource highErrorRateAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${namePrefix}-high-error-rate'
  location: 'global'
  tags: tags
  properties: {
    description: 'Triggers when there are more than 10 HTTP 5xx errors in 5 minutes'
    severity: 2
    enabled: true
    scopes: [webAppId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Http5xxErrors'
          metricName: 'Http5xx'
          operator: 'GreaterThan'
          threshold: 10
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: actionGroupId
  }
}

// --- Alert: Health Check Failures ---
resource healthCheckAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${namePrefix}-health-check-failure'
  location: 'global'
  tags: tags
  properties: {
    description: 'Triggers when health check success rate drops below 80%'
    severity: 1
    enabled: true
    scopes: [webAppId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HealthCheckStatus'
          metricName: 'HealthCheckStatus'
          operator: 'LessThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: actionGroupId
  }
}

// --- Alert: High Response Time ---
resource highResponseTimeAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${namePrefix}-high-response-time'
  location: 'global'
  tags: tags
  properties: {
    description: 'Triggers when average response time exceeds 30 seconds'
    severity: 3
    enabled: true
    scopes: [webAppId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ResponseTime'
          metricName: 'HttpResponseTime'
          operator: 'GreaterThan'
          threshold: 30
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: actionGroupId
  }
}

// --- Alert: Unusual Request Volume (Log-based) ---
resource unusualVolumeAlert 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: '${namePrefix}-unusual-volume'
  location: resourceGroup().location
  tags: tags
  properties: {
    description: 'Triggers when there are more than 500 requests in 1 hour'
    severity: 3
    enabled: true
    scopes: [logAnalyticsWorkspaceId]
    evaluationFrequency: 'PT15M'
    windowSize: 'PT1H'
    criteria: {
      allOf: [
        {
          query: 'AppServiceHTTPLogs | where _ResourceId =~ "${webAppId}" | summarize RequestCount = count() by bin(TimeGenerated, 1h) | where RequestCount > 500'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: !empty(alertEmailAddress) ? [actionGroup.id] : []
    }
  }
}
