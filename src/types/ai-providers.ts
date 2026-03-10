export interface AiModel {
  id: string;
  label: string;
  capabilities: string[];
}

export interface AiProviderGroup {
  name: string;
  models: AiModel[];
}

export interface AiProviderResponse {
  providers: AiProviderGroup[];
  last_updated: string;
}
