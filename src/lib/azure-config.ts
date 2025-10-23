/**
 * Azure Storage Configuration
 * 
 * This module provides configuration for Azure Table Storage.
 * Configuration is loaded from environment variables.
 * 
 * Required environment variables:
 * - VITE_AZURE_STORAGE_ACCOUNT_NAME: Your Azure Storage Account name
 * - VITE_AZURE_STORAGE_SAS_TOKEN: SAS token with appropriate permissions
 * 
 * Optional environment variables:
 * - VITE_AZURE_STORAGE_ENDPOINT: Custom endpoint (defaults to standard Azure endpoint)
 * - VITE_AZURE_GAMES_TABLE_NAME: Name of the games table (defaults to 'games')
 * - VITE_AZURE_CATEGORIES_TABLE_NAME: Name of the categories table (defaults to 'categories')
 */

export interface AzureConfig {
  accountName: string;
  sasToken?: string;
  accountKey?: string;
  endpoint?: string;
  tables: {
    games: string;
    categories: string;
  };
}

/**
 * Load Azure Storage configuration from environment variables
 */
export function getAzureConfig(): AzureConfig {
  const accountName = import.meta.env.VITE_AZURE_STORAGE_ACCOUNT_NAME;
  const sasToken = import.meta.env.VITE_AZURE_STORAGE_SAS_TOKEN;
  const accountKey = import.meta.env.VITE_AZURE_STORAGE_ACCOUNT_KEY;

  if (!accountName) {
    throw new Error(
      'VITE_AZURE_STORAGE_ACCOUNT_NAME environment variable is required. ' +
      'Please set it in your .env file.'
    );
  }

  if (!sasToken && !accountKey) {
    throw new Error(
      'Either VITE_AZURE_STORAGE_SAS_TOKEN or VITE_AZURE_STORAGE_ACCOUNT_KEY ' +
      'environment variable is required. Please set one in your .env file.'
    );
  }

  return {
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
