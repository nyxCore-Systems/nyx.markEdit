import { NativeModule } from '../nativeModule';

export enum AIAction {
  improve = 'improve',
  shorten = 'shorten',
  expand = 'expand',
  fixGrammar = 'fixGrammar',
  toneProfessional = 'toneProfessional',
  toneCasual = 'toneCasual',
  toneFriendly = 'toneFriendly',
  toneAcademic = 'toneAcademic',
}

export interface AIRefactorResponse {
  result?: string;
  error?: string;
}

export interface AIPersona {
  id: string;
  name: string;
  description?: string;
  // 'mcp' (global personas via MCP token) or 'studio' (Persona Studio circles).
  source?: string;
  circleId?: string;
  circleName?: string;
}

export interface AIPersonaListResponse {
  personas?: AIPersona[];
  error?: string;
}

export interface AIKnowledgeConfig {
  // Subset of ['off', 'project', 'global', 'all'], always contains 'off'.
  availableScopes?: string[];
  defaultScope?: string;
  error?: string;
}

/**
 * @shouldExport true
 * @invokePath ai
 * @bridgeName NativeBridgeAI
 */
export interface NativeModuleAI extends NativeModule {
  isConfigured(): Promise<boolean>;
  refactor(args: { action: AIAction; selection: string; context?: string }): Promise<string>;

  // nyxCore: personas and knowledge-grounded rewriting.
  //
  // All return JSON-encoded strings (parsed on the web side), matching the
  // convention used by refactor. listPersonas yields an AIPersonaListResponse,
  // getKnowledgeConfig yields an AIKnowledgeConfig, refactorWithPersona yields
  // an AIRefactorResponse.
  listPersonas(): Promise<string>;
  getKnowledgeConfig(): Promise<string>;
  refactorWithPersona(args: {
    personaID: string;
    personaName: string;
    circleID?: string;
    selection: string;
    context?: string;
    knowledgeScope: string;
  }): Promise<string>;
}
