/**
 * Azure Storage Configuration
 *
 * This module provides configuration for Azure Table Storage.
 * Configuration is loaded from environment variables.
 *
 * The application is deployed once per environment as a single shared
 * service (see specs/003-shared-entry-scale/). There is no per-instance
 * identifier in any name here: a logical instance is a Table Storage record
 * partitioned inside the shared tables, not a separate storage account or
 * deployment. Adding a logical instance therefore never changes this
 * configuration.
 *
 * Required environment variables:
 * - VITE_AZURE_STORAGE_SAS_TOKEN: SAS token with appropriate permissions
 *   (or VITE_AZURE_STORAGE_ACCOUNT_KEY for local testing)
 *
 * The shared storage account name is resolved in this order:
 * 1. VITE_AZURE_STORAGE_ACCOUNT_NAME, when supplied by the deployment
 * 2. Otherwise derived deterministically from VITE_AZURE_ENVIRONMENT and
 *    VITE_AZURE_BASE_NAME, matching infra/shared/main.bicep
 *
 * Optional environment variables:
 * - VITE_AZURE_ENVIRONMENT: dev | staging | prod (defaults to 'dev')
 * - VITE_AZURE_BASE_NAME: base name prefix (defaults to 'gamevault')
 * - VITE_AZURE_STORAGE_ENDPOINT: Custom endpoint (defaults to standard Azure endpoint)
 * - VITE_AZURE_GAMES_TABLE_NAME: Name of the shared games table (defaults to 'games')
 * - VITE_AZURE_CATEGORIES_TABLE_NAME: Name of the shared categories table (defaults to 'categories')
 */

export type AzureEnvironment = 'dev' | 'staging' | 'prod';

export interface AzureConfig {
  environment: AzureEnvironment;
  accountName: string;
  sasToken?: string;
  accountKey?: string;
  endpoint?: string;
  tables: {
    games: string;
    categories: string;
  };
}

const DEFAULT_BASE_NAME = 'gamevault';
const DEFAULT_ENVIRONMENT: AzureEnvironment = 'dev';

function resolveEnvironment(): AzureEnvironment {
  const raw = (import.meta.env.VITE_AZURE_ENVIRONMENT || '').trim().toLowerCase();
  if (raw === 'dev' || raw === 'staging' || raw === 'prod') {
    return raw;
  }
  if (raw) {
    throw new Error(
      `VITE_AZURE_ENVIRONMENT must be one of 'dev', 'staging', or 'prod' (received '${raw}').`
    );
  }
  return DEFAULT_ENVIRONMENT;
}

/**
 * Deterministic shared storage account name.
 *
 * Must stay in sync with `storageAccountName` in infra/shared/main.bicep:
 *   toLower(replace('st${baseName}shared${environment}', '-', ''))
 */
export function sharedStorageAccountName(
  environment: AzureEnvironment,
  baseName: string = DEFAULT_BASE_NAME
): string {
  return `st${baseName}shared${environment}`.replace(/-/g, '').toLowerCase();
}

/**
 * Load Azure Storage configuration from environment variables
 */
export function getAzureConfig(): AzureConfig {
  const environment = resolveEnvironment();
  const baseName = (import.meta.env.VITE_AZURE_BASE_NAME || DEFAULT_BASE_NAME).trim();
  const explicitAccountName = (import.meta.env.VITE_AZURE_STORAGE_ACCOUNT_NAME || '').trim();
  const accountName = explicitAccountName || sharedStorageAccountName(environment, baseName);
  const sasToken = import.meta.env.VITE_AZURE_STORAGE_SAS_TOKEN;
  const accountKey = import.meta.env.VITE_AZURE_STORAGE_ACCOUNT_KEY;

  if (!accountName) {
    throw new Error(
      'Unable to resolve the shared Azure Storage account name. Set ' +
      'VITE_AZURE_STORAGE_ACCOUNT_NAME, or set VITE_AZURE_ENVIRONMENT so it ' +
      'can be derived from the shared deployment naming convention.'
    );
  }

  if (!sasToken && !accountKey) {
    throw new Error(
      'Either VITE_AZURE_STORAGE_SAS_TOKEN or VITE_AZURE_STORAGE_ACCOUNT_KEY ' +
      'environment variable is required. Please set one in your .env file.'
    );
  }

  return {
    environment,
    accountName,
    sasToken,
    accountKey,
    endpoint: import.meta.env.VITE_AZURE_STORAGE_ENDPOINT,
    tables: {
      games: import.meta.env.VITE_AZURE_GAMES_TABLE_NAME || 'games',
      categories: import.meta.env.VITE_AZURE_CATEGORIES_TABLE_NAME || 'categories',
    },
  };
}

/**
 * Validate that the Azure configuration is properly set
 */
export function validateAzureConfig(): { valid: boolean; error?: string } {
  try {
    getAzureConfig();
    return { valid: true };
  } catch (error) {
    return {
      valid: false,
      error: error instanceof Error ? error.message : 'Unknown configuration error',
    };
  }
}
