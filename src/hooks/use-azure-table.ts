/**
 * Azure Table Storage React Hooks
 * 
 * These hooks provide a React-friendly interface to Azure Table Storage,
 * similar to the useKV hook but backed by Azure instead of local storage.
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import { AzureTableStorageService, TableEntity } from '@/lib/azure-storage';
import { getAzureConfig } from '@/lib/azure-config';

// Singleton instance of the Azure service
let azureServiceInstance: AzureTableStorageService | null = null;

function getAzureService(): AzureTableStorageService {
  if (!azureServiceInstance) {
    const config = getAzureConfig();
    azureServiceInstance = new AzureTableStorageService({
      accountName: config.accountName,
      sasToken: config.sasToken,
      accountKey: config.accountKey,
      tablesEndpoint: config.endpoint,
    });
  }
  return azureServiceInstance;
}

/**
 * Entity structure for Azure Table Storage
 * Uses a single partition for simplicity, with RowKey as the unique identifier
 */
interface AzureEntity<T> extends TableEntity {
  PartitionKey: string;
  RowKey: string;
  data: string; // JSON-serialized data
}

/**
 * Hook to manage data in Azure Table Storage
 * 
 * @param tableName - Name of the Azure Table
 * @param defaultValue - Default value if no data exists
 * @param partitionKey - Partition key (defaults to 'default')
 * @returns Tuple of [data, setData, loading, error]
 */
export function useAzureTable<T>(
  tableName: string,
  defaultValue: T,
  partitionKey: string = 'default'
): [T, (value: T | ((prev: T) => T)) => void, boolean, Error | null] {
  const [data, setDataState] = useState<T>(defaultValue);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<Error | null>(null);
  const isMountedRef = useRef(true);
  const rowKey = 'data'; // Single row per table for simple key-value storage

  // Load data on mount
  useEffect(() => {
    isMountedRef.current = true;
    
    const loadData = async () => {
      try {
        setLoading(true);
        setError(null);
        
        const service = getAzureService();
        const entity = await service.getEntity<AzureEntity<T>>(
          tableName,
          partitionKey,
          rowKey
        );

        if (isMountedRef.current) {
          if (entity && entity.data) {
            try {
              const parsedData = JSON.parse(entity.data);
              setDataState(parsedData);
            } catch (parseError) {
              console.error('Failed to parse data from Azure Table Storage:', parseError);
              setDataState(defaultValue);
            }
          } else {
            // No data exists, use default and create initial entry
            setDataState(defaultValue);
            // Optionally, save the default value to Azure
            await service.upsertEntity<AzureEntity<T>>(tableName, {
              PartitionKey: partitionKey,
              RowKey: rowKey,
              data: JSON.stringify(defaultValue),
            });
          }
          setLoading(false);
        }
      } catch (err) {
        console.error('Failed to load data from Azure Table Storage:', err);
        if (isMountedRef.current) {
          setError(err instanceof Error ? err : new Error('Unknown error'));
          setDataState(defaultValue);
          setLoading(false);
        }
      }
    };

    loadData();

    return () => {
      isMountedRef.current = false;
    };
  }, [tableName, partitionKey]); // Intentionally omit defaultValue to avoid re-fetching

  // Save data to Azure
  const setData = useCallback(
    async (value: T | ((prev: T) => T)) => {
      const newValue = typeof value === 'function' 
        ? (value as (prev: T) => T)(data)
        : value;

      // Optimistically update local state
      setDataState(newValue);

      try {
        const service = getAzureService();
        await service.upsertEntity<AzureEntity<T>>(tableName, {
          PartitionKey: partitionKey,
          RowKey: rowKey,
          data: JSON.stringify(newValue),
        });
      } catch (err) {
        console.error('Failed to save data to Azure Table Storage:', err);
        setError(err instanceof Error ? err : new Error('Failed to save data'));
        // Optionally revert the optimistic update
        // In this implementation, we keep the local change to avoid data loss
      }
    },
    [data, tableName, partitionKey, rowKey]
  );

  return [data, setData, loading, error];
}

/**
 * Hook to manage a list of items in Azure Table Storage
 * Each item gets its own row, using the item's ID as the RowKey
 * 
 * @param tableName - Name of the Azure Table
 * @param defaultValue - Default value if no data exists
 * @param partitionKey - Partition key (defaults to 'default')
 * @param getItemId - Function to extract ID from an item
 * @returns Tuple of [data, setData, loading, error]
 */
export function useAzureTableList<T extends { id: string }>(
  tableName: string,
  defaultValue: T[],
  partitionKey: string = 'default',
  getItemId: (item: T) => string = (item) => item.id
): [T[], (value: T[] | ((prev: T[]) => T[])) => void, boolean, Error | null] {
  const [data, setDataState] = useState<T[]>(defaultValue);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<Error | null>(null);
  const isMountedRef = useRef(true);

  // Load data on mount
  useEffect(() => {
    isMountedRef.current = true;
    
    const loadData = async () => {
      try {
        setLoading(true);
        setError(null);
        
        console.log(`[Azure] Loading data from table: ${tableName}`);
        
        const service = getAzureService();
        const entities = await service.queryEntities<AzureEntity<T>>(
          tableName,
          { filter: `PartitionKey eq '${partitionKey}'` }
        );

        console.log(`[Azure] Loaded ${entities.length} entities from ${tableName}`);

        if (isMountedRef.current) {
          if (entities && entities.length > 0) {
            const items = entities
              .map(entity => {
                try {
                  return JSON.parse(entity.data) as T;
                } catch (parseError) {
                  console.error('[Azure] Failed to parse entity:', parseError);
                  return null;
                }
              })
              .filter((item): item is T => item !== null);
            
            console.log(`[Azure] Parsed ${items.length} items from ${tableName}`);
            setDataState(items);
          } else {
            console.log(`[Azure] No entities found in ${tableName}, using default value`);
            setDataState(defaultValue);
          }
          setLoading(false);
        }
      } catch (err) {
        console.error('[Azure] Failed to load data from Azure Table Storage:', err);
        if (isMountedRef.current) {
          setError(err instanceof Error ? err : new Error('Unknown error'));
          setDataState(defaultValue);
          setLoading(false);
        }
      }
    };

    loadData();

    return () => {
      isMountedRef.current = false;
    };
  }, [tableName, partitionKey]);

  // Save data to Azure
  const setData = useCallback(
    async (value: T[] | ((prev: T[]) => T[])) => {
      // Use the updater function pattern to get current state
      setDataState((currentData) => {
        const newValue = typeof value === 'function' 
          ? (value as (prev: T[]) => T[])(currentData)
          : value;

        // Perform async save operation
        (async () => {
          try {
            const service = getAzureService();
            
            console.log(`[Azure] Saving ${newValue.length} items to table: ${tableName}`);
            
            // Find items to delete (items in old data but not in new data)
            const oldIds = new Set(currentData.map(getItemId));
            const newIds = new Set(newValue.map(getItemId));
            const idsToDelete = Array.from(oldIds).filter(id => !newIds.has(id));

            // Delete removed items
            if (idsToDelete.length > 0) {
              console.log(`[Azure] Deleting ${idsToDelete.length} items`);
              for (const id of idsToDelete) {
                await service.deleteEntity(tableName, partitionKey, String(id));
              }
            }

            // Upsert new/updated items
            console.log(`[Azure] Upserting ${newValue.length} items`);
            for (const item of newValue) {
              const itemId = getItemId(item);
              await service.upsertEntity<AzureEntity<T>>(tableName, {
                PartitionKey: partitionKey,
                RowKey: itemId,
                data: JSON.stringify(item),
              });
            }
            
            console.log(`[Azure] Successfully saved data to ${tableName}`);
          } catch (err) {
            console.error('[Azure] Failed to save data to Azure Table Storage:', err);
            setError(err instanceof Error ? err : new Error('Failed to save data'));
          }
        })();

        return newValue;
      });
    },
    [tableName, partitionKey, getItemId]
  );

  return [data, setData, loading, error];
}
