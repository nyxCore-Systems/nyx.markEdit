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

/**
 * @shouldExport true
 * @invokePath ai
 * @bridgeName NativeBridgeAI
 */
export interface NativeModuleAI extends NativeModule {
  isConfigured(): Promise<boolean>;
  refactor(args: { action: AIAction; selection: string; context?: string }): Promise<string>;
}
