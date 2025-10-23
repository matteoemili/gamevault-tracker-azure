/// <reference types="vite/client" />
declare const GITHUB_RUNTIME_PERMANENT_NAME: string
declare const BASE_KV_SERVICE_URL: string

interface ImportMetaEnv {
  readonly VITE_AZURE_STORAGE_ACCOUNT_NAME: string
  readonly VITE_AZURE_STORAGE_SAS_TOKEN?: string
  readonly VITE_AZURE_STORAGE_ACCOUNT_KEY?: string
  readonly VITE_AZURE_STORAGE_ENDPOINT?: string
  readonly VITE_AZURE_GAMES_TABLE_NAME?: string
  readonly VITE_AZURE_CATEGORIES_TABLE_NAME?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}