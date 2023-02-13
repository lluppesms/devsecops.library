// --------------------------------------------------------------------------------
// Main Bicep File to deploy all Azure Resources for a Durable Function app
// Note: Bicep modules are used from the repository defined in bicepconfig.json
// --------------------------------------------------------------------------------
// NOTE: To make this pipeline work, your service principal may need to be in the
//   "acr pull" role for the container registry.
// --------------------------------------------------------------------------------
// To deploy this Bicep manually:
// 	 az login
//   az account set --subscription <subscriptionId>
//   az deployment group create -n main-deploy-20230213T110000Z --resource-group rg_durable_functions --template-file 'main-durable-function-app-bcr.bicep' --parameters orgPrefix=xxx appPrefix=durabledemo environmentCode=dev
// --------------------------------------------------------------------------------
@allowed(['dev','demo','qa','stg','prod'])
param environmentCode string = 'dev'
param location string = resourceGroup().location
param orgPrefix string = 'org'
param appPrefix string = 'app'
param appSuffix string = '' // '-1' 
@allowed(['Standard_LRS','Standard_GRS','Standard_RAGRS'])
param storageSku string = 'Standard_LRS'
param functionAppSku string = 'Y1'
param functionAppSkuFamily string = 'Y'
param functionAppSkuTier string = 'Dynamic'
param keyVaultOwnerUserId1 string = ''
param keyVaultOwnerUserId2 string = ''
param twilioAccountSid string = ''
param twilioAuthToken string = ''
param twilioPhoneNumber string = ''
param runDateTime string = utcNow()

// --------------------------------------------------------------------------------
var deploymentSuffix = '-${runDateTime}'
var commonTags = {         
  LastDeployed: runDateTime
  Application: appPrefix
  Organization: orgPrefix
  Environment: environmentCode
}

// --------------------------------------------------------------------------------
module resourceNames '../Bicep/resourcenames.bicep' = {
  name: 'resourcenames${deploymentSuffix}'
  params: {
    orgPrefix: orgPrefix
    appPrefix: appPrefix
    environment: environmentCode
    appSuffix: appSuffix
    functionStorageNameSuffix: 'store'
    dataStorageNameSuffix: 'data'
  }
}

// --------------------------------------------------------------------------------
module functionStorageModule 'br/mybicepregistry:storageaccount:LATEST' = {
  name: 'functionstorage${deploymentSuffix}'
  params: {
    storageSku: storageSku
    storageAccountName: resourceNames.outputs.functionStorageName
    location: location
    commonTags: commonTags
  }
}

module functionModule 'br/mybicepregistry:functionapp:LATEST' = {
  name: 'function${deploymentSuffix}'
  dependsOn: [ functionStorageModule ]
  params: {
    functionAppName: resourceNames.outputs.functionAppName
    functionAppServicePlanName: resourceNames.outputs.functionAppServicePlanName
    functionInsightsName: resourceNames.outputs.functionInsightsName

    appInsightsLocation: location
    location: location
    commonTags: commonTags

    functionKind: 'functionapp,linux'
    functionAppSku: functionAppSku
    functionAppSkuFamily: functionAppSkuFamily
    functionAppSkuTier: functionAppSkuTier
    functionStorageAccountName: functionStorageModule.outputs.name
  }
}

module dataStorageModule 'br/mybicepregistry:storageaccount:LATEST' = {
  name: 'datastorage${deploymentSuffix}'
  params: {
    storageAccountName: resourceNames.outputs.dataStorageName
    location: location
    commonTags: commonTags
    storageSku: storageSku
  }
}
module keyVaultModule 'br/mybicepregistry:keyvault:LATEST' = {
  name: 'keyvault${deploymentSuffix}'
  dependsOn: [ functionModule ]
  params: {
    keyVaultName: resourceNames.outputs.keyVaultName
    location: location
    commonTags: commonTags
    adminUserObjectIds: [ keyVaultOwnerUserId1, keyVaultOwnerUserId2 ]
    applicationUserObjectIds: [ functionModule.outputs.principalId ]
  }
}

module keyVaultSecret1 'br/mybicepregistry:keyvaultsecret:LATEST' = {
  name: 'keyVaultSecret1${deploymentSuffix}'
  dependsOn: [ keyVaultModule, functionModule ]
  params: {
    keyVaultName: keyVaultModule.outputs.name
    secretName: 'TwilioAccountSid'
    secretValue: twilioAccountSid
  }
}

module keyVaultSecret2 'br/mybicepregistry:keyvaultsecret:LATEST' = {
  name: 'keyVaultSecret2${deploymentSuffix}'
  dependsOn: [ keyVaultModule, functionModule ]
  params: {
    keyVaultName: keyVaultModule.outputs.name
    secretName: 'TwilioAuthToken'
    secretValue: twilioAuthToken
  }
}

module keyVaultSecret3 'br/mybicepregistry:keyvaultsecret:LATEST' = {
  name: 'keyVaultSecret3${deploymentSuffix}'
  dependsOn: [ keyVaultModule, functionModule ]
  params: {
    keyVaultName: keyVaultModule.outputs.name
    secretName: 'TwilioPhoneNumber'
    secretValue: twilioPhoneNumber
  }
}
module keyVaultSecret4 'br/mybicepregistry:keyvaultsecretstorageconnection:LATEST' = {
  name: 'keyVaultSecret4${deploymentSuffix}'
  dependsOn: [ keyVaultModule, dataStorageModule ]
  params: {
    keyVaultName: keyVaultModule.outputs.name
    keyName: 'DataStorageConnectionAppSetting'
    storageAccountName: dataStorageModule.outputs.name
  }
}
module functionAppSettingsModule 'br/mybicepregistry:functionappsettings:LATEST' = {
  name: 'functionAppSettings${deploymentSuffix}'
  // dependsOn: [  keyVaultSecrets ]
  params: {
    functionAppName: functionModule.outputs.name
    functionStorageAccountName: functionStorageModule.outputs.name
    functionInsightsKey: functionModule.outputs.insightsKey
    customAppSettings: {
      TwilioAccountSid: '@Microsoft.KeyVault(VaultName=${keyVaultModule.outputs.name};SecretName=TwilioAccountSid)'
      TwilioAuthToken: '@Microsoft.KeyVault(VaultName=${keyVaultModule.outputs.name};SecretName=TwilioAuthToken)'
      TwilioPhoneNumber: '@Microsoft.KeyVault(VaultName=${keyVaultModule.outputs.name};SecretName=TwilioPhoneNumber)'
      DataStorageConnectionAppSetting: '@Microsoft.KeyVault(VaultName=${keyVaultModule.outputs.name};SecretName=DataStorageConnectionAppSetting)'
    }
  }
}
