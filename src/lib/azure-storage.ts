/**
 * Azure Table Storage Service
 * 
 * This module provides a REST API interface to Azure Table Storage.
 * It uses Shared Access Signature (SAS) tokens for authentication.
 * 
 * Azure Table Storage uses PartitionKey and RowKey as the primary key.
 * - PartitionKey: Used for data distribution and scaling
 * - RowKey: Unique identifier within a partition
 */

export interface AzureStorageConfig {
  accountName: string;
  sasToken?: string;
  accountKey?: string;
  tablesEndpoint?: string;
}

export interface TableEntity {
  PartitionKey: string;
  RowKey: string;
  Timestamp?: string;
  [key: string]: any;
}

export interface QueryOptions {
  filter?: string;
  select?: string[];
  top?: number;
}

export class AzureTableStorageService {
  private accountName: string;
  private sasToken?: string;
  private accountKey?: string;
  private baseUrl: string;

  constructor(config: AzureStorageConfig) {
    this.accountName = config.accountName;
    this.sasToken = config.sasToken;
    this.accountKey = config.accountKey;
    this.baseUrl = config.tablesEndpoint || 
      `https://${config.accountName}.table.core.windows.net`;
  }

  /**
   * Generate Shared Key Lite signature for authentication
   */
  private async generateSharedKeySignature(
    method: string,
    url: string,
    date: string,
    contentLength: string = ''
  ): Promise<string> {
    if (!this.accountKey) {
      throw new Error('Account key is required for Shared Key authentication');
    }

    const urlObj = new URL(url);
    const canonicalizedResource = `/${this.accountName}${urlObj.pathname}`;
    
    const stringToSign = `${date}\n${canonicalizedResource}`;

    // Decode base64 key
    const keyBytes = Uint8Array.from(atob(this.accountKey), c => c.charCodeAt(0));
    
    // Import key for HMAC
    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      keyBytes,
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign']
    );

    // Sign the string
    const signature = await crypto.subtle.sign(
      'HMAC',
      cryptoKey,
      new TextEncoder().encode(stringToSign)
    );

    // Convert to base64
    const signatureBase64 = btoa(String.fromCharCode(...new Uint8Array(signature)));
    
    return `SharedKeyLite ${this.accountName}:${signatureBase64}`;
  }

  /**
   * Constructs the full URL for a table operation
   */
  private getTableUrl(tableName: string, partitionKey?: string, rowKey?: string): string {
    let url = `${this.baseUrl}/${tableName}`;
    
    if (partitionKey && rowKey) {
      url += `(PartitionKey='${encodeURIComponent(partitionKey)}',RowKey='${encodeURIComponent(rowKey)}')`;
    }
    
    // Append SAS token if using SAS authentication
    if (this.sasToken) {
      url += `?${this.sasToken.startsWith('?') ? this.sasToken.substring(1) : this.sasToken}`;
    }
    
    return url;
  }

  /**
   * Get headers for the request with proper authentication
   */
  private async getHeaders(
    method: string,
    url: string,
    additionalHeaders: Record<string, string> = {}
  ): Promise<Record<string, string>> {
    const headers: Record<string, string> = {
      'Accept': 'application/json;odata=nometadata',
      'x-ms-version': '2024-11-04',
      ...additionalHeaders,
    };

    if (this.accountKey) {
      // Use Shared Key authentication
      const date = new Date().toUTCString();
      headers['x-ms-date'] = date;
      headers['Authorization'] = await this.generateSharedKeySignature(method, url, date);
    }
    // If using SAS token, it's already in the URL

    return headers;
  }

  /**
   * Query entities from a table
   */
  async queryEntities<T extends TableEntity>(
    tableName: string,
    options?: QueryOptions
  ): Promise<T[]> {
    let url = this.getTableUrl(tableName);
    
    const params: string[] = [];
    if (options?.filter) {
      params.push(`$filter=${encodeURIComponent(options.filter)}`);
    }
    if (options?.select) {
      params.push(`$select=${options.select.join(',')}`);
    }
    if (options?.top) {
      params.push(`$top=${options.top}`);
    }
    
    if (params.length > 0) {
      const separator = url.includes('?') ? '&' : '?';
      url += separator + params.join('&');
    }

    const headers = await this.getHeaders('GET', url);

    const response = await fetch(url, {
      method: 'GET',
      headers,
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Failed to query entities: ${response.status} ${errorText}`);
    }

    const data = await response.json();
    return data.value || [];
  }

  /**
   * Get a specific entity by PartitionKey and RowKey
   */
  async getEntity<T extends TableEntity>(
    tableName: string,
    partitionKey: string,
    rowKey: string
  ): Promise<T | null> {
    const url = this.getTableUrl(tableName, partitionKey, rowKey);
    const headers = await this.getHeaders('GET', url);

    const response = await fetch(url, {
      method: 'GET',
      headers,
    });

    if (response.status === 404) {
      return null;
    }

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Failed to get entity: ${response.status} ${errorText}`);
    }

    return await response.json();
  }

  /**
   * Insert or replace an entity (upsert)
   */
  async upsertEntity<T extends TableEntity>(
    tableName: string,
    entity: T
  ): Promise<void> {
    if (!entity.PartitionKey || !entity.RowKey) {
      throw new Error('Entity must have PartitionKey and RowKey');
    }

    const url = this.getTableUrl(tableName, entity.PartitionKey, entity.RowKey);
    const headers = await this.getHeaders('PUT', url, {
      'Content-Type': 'application/json',
    });

    const response = await fetch(url, {
      method: 'PUT',
      headers,
      body: JSON.stringify(entity),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`[Azure Storage] Upsert failed:`, {
        status: response.status,
        statusText: response.statusText,
        tableName,
        partitionKey: entity.PartitionKey,
        rowKey: entity.RowKey,
        errorText,
        url: url.split('?')[0], // Don't log SAS token
      });
      throw new Error(`Failed to upsert entity: ${response.status} ${errorText}`);
    }
  }

  /**
   * Insert a new entity (fails if entity already exists)
   */
  async insertEntity<T extends TableEntity>(
    tableName: string,
    entity: T
  ): Promise<void> {
    if (!entity.PartitionKey || !entity.RowKey) {
      throw new Error('Entity must have PartitionKey and RowKey');
    }

    const url = this.getTableUrl(tableName);
    const headers = await this.getHeaders('POST', url, {
      'Content-Type': 'application/json',
      'Prefer': 'return-no-content',
    });

    const response = await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(entity),
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Failed to insert entity: ${response.status} ${errorText}`);
    }
  }

  /**
   * Update an existing entity (merge)
   */
  async updateEntity<T extends Partial<TableEntity>>(
    tableName: string,
    partitionKey: string,
    rowKey: string,
    entity: T
  ): Promise<void> {
    const url = this.getTableUrl(tableName, partitionKey, rowKey);
    const headers = await this.getHeaders('PATCH', url, {
      'Content-Type': 'application/json',
    });

    const response = await fetch(url, {
      method: 'PATCH',
      headers,
      body: JSON.stringify(entity),
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Failed to update entity: ${response.status} ${errorText}`);
    }
  }

  /**
   * Delete an entity
   */
  async deleteEntity(
    tableName: string,
    partitionKey: string,
    rowKey: string
  ): Promise<void> {
    const url = this.getTableUrl(tableName, partitionKey, rowKey);
    const headers = await this.getHeaders('DELETE', url, {
      'If-Match': '*', // Optimistic concurrency - delete regardless of ETag
    });

    const response = await fetch(url, {
      method: 'DELETE',
      headers,
    });

    if (response.status === 404) {
      // Entity doesn't exist, consider it a success
      return;
    }

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Failed to delete entity: ${response.status} ${errorText}`);
    }
  }

  /**
   * Batch operations (for future optimization)
   * Azure Table Storage supports batch operations for entities in the same partition
   */
  async batchOperations(
    tableName: string,
    operations: Array<{
      type: 'insert' | 'update' | 'delete' | 'upsert';
      entity?: TableEntity;
      partitionKey?: string;
      rowKey?: string;
    }>
  ): Promise<void> {
    // Note: Batch operations require multipart/mixed content type
    // and are more complex. For simplicity, we'll execute sequentially for now.
    for (const op of operations) {
      switch (op.type) {
        case 'insert':
          if (op.entity) await this.insertEntity(tableName, op.entity);
          break;
        case 'update':
          if (op.entity && op.partitionKey && op.rowKey) {
            await this.updateEntity(tableName, op.partitionKey, op.rowKey, op.entity);
          }
          break;
        case 'delete':
          if (op.partitionKey && op.rowKey) {
            await this.deleteEntity(tableName, op.partitionKey, op.rowKey);
          }
          break;
        case 'upsert':
          if (op.entity) await this.upsertEntity(tableName, op.entity);
          break;
      }
    }
  }
}
