export interface AiModel {
  id: string;
  label: string;
  capabilities: string[];
  context_window: number;
}

export interface AiProviderGroup {
  name: string;
  models: AiModel[];
}

export interface AiProviderResponse {
  providers: AiProviderGroup[];
  last_updated: string;
}
