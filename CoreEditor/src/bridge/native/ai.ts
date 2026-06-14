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
}

export interface AIPersonaListResponse {
  personas?: AIPersona[];
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
  // Both return JSON-encoded strings (parsed on the web side), matching the
  // convention used by refactor. listPersonas yields an AIPersonaListResponse,
  // refactorWithPersona yields an AIRefactorResponse.
  listPersonas(): Promise<string>;
  refactorWithPersona(args: {
    personaID: string;
    personaName: string;
    selection: string;
    context?: string;
    useKnowledge: boolean;
  }): Promise<string>;
}
