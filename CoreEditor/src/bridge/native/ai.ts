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
  // Non-fatal note about a degraded run, e.g. knowledge retrieval failed and
  // the rewrite went ahead ungrounded. Shown next to the result, never instead.
  warning?: string;
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

/**
 * One selectable grounding source for AI actions.
 *
 * `id` is the opaque routing key handed back to the native side. The legacy
 * scope strings ('off', 'project', 'global', 'all') are valid ids, and named
 * sources configured in Settings use 'project:<uuid>' / 'collection:<uuid>'.
 */
export interface AIKnowledgeSource {
  id: string;
  name: string;
  // 'off' | 'project' | 'collection' | 'all'
  kind: string;
}

export interface AIKnowledgeConfig {
  // Subset of ['off', 'project', 'global', 'all'], always contains 'off'.
  availableScopes?: string[];
  defaultScope?: string;
  // Preferred over availableScopes when present: carries display names for
  // the project/collection each entry actually points at.
  sources?: AIKnowledgeSource[];
  defaultSourceId?: string;
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
    // A knowledge source id (see AIKnowledgeSource); legacy scope strings still apply.
    knowledgeScope: string;
  }): Promise<string>;

  /**
   * Free-form instruction over the selection, optionally grounded in a
   * knowledge source. Yields an AIRefactorResponse like the other rewrites.
   */
  refactorWithPrompt(args: {
    prompt: string;
    selection: string;
    context?: string;
    knowledgeSource: string;
  }): Promise<string>;
}
