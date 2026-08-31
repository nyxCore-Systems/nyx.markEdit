import { EditorView, ViewPlugin, ViewUpdate } from '@codemirror/view';
import { EditorSelection } from '@codemirror/state';
import { AIAction, AIKnowledgeConfig, AIKnowledgeSource, AIPersona, AIPersonaListResponse, AIRefactorResponse } from '../../bridge/native/ai';
import { globalState } from '../../common/store';
import { clampPosition, computeToolbarPosition } from './positioning';
import './index.css';

import { isActive as isWritingToolsActive } from '../writingTools';

interface ToolbarLabels {
  improve: string;
  shorten: string;
  expand: string;
  fixGrammar: string;
  tone: string;
  toneProfessional: string;
  toneCasual: string;
  toneFriendly: string;
  toneAcademic: string;
  persona: string;
  personaLoading: string;
  noPersonas: string;
  knowledgeTitle: string;
  scopeOff: string;
  scopeProject: string;
  scopeGlobal: string;
  scopeAll: string;
  prompt: string;
  promptPlaceholder: string;
  promptRun: string;
  promptHint: string;
  promptExamplesTitle: string;
  promptRecentTitle: string;
  loading: string;
  notConfigured: string;
}

/**
 * Starter instructions offered the first time the prompt field is opened.
 *
 * A blank box is the hardest thing to answer: these show the shape of a useful
 * instruction — a verb, a target, a source — and are replaced by the user's own
 * recent prompts as soon as there are any.
 */
const promptExamples = [
  'Expand this using the relevant facts from the knowledge base',
  'Turn these bullet points into full paragraphs',
  'Rewrite this in a formal tone',
  'Summarise this as three bullet points',
];

const defaultLabels: ToolbarLabels = {
  improve: 'Improve',
  shorten: 'Shorten',
  expand: 'Expand',
  fixGrammar: 'Fix Grammar',
  tone: 'Tone',
  toneProfessional: 'Professional',
  toneCasual: 'Casual',
  toneFriendly: 'Friendly',
  toneAcademic: 'Academic',
  persona: 'Persona',
  personaLoading: 'Loading personas…',
  noPersonas: 'No personas (check nyxCore settings)',
  knowledgeTitle: 'Knowledge',
  scopeOff: 'Off',
  scopeProject: 'Project',
  scopeGlobal: 'Global',
  scopeAll: 'All',
  prompt: 'Prompt',
  promptPlaceholder: 'What should happen with this text?',
  promptRun: 'Run',
  promptHint: '↵ to run · ⇧↵ for a new line',
  promptExamplesTitle: 'Try',
  promptRecentTitle: 'Recent',
  loading: 'Thinking…',
  notConfigured: 'Configure AI in Settings',
};

const promptHistoryKey = 'markedit.ai.promptHistory';
const promptHistoryLimit = 5;

/**
 * Recently used instructions, newest first. Browser storage can throw outright
 * (private windows, blocked site data), so every access is guarded and a failure
 * degrades to "no history" rather than breaking the panel.
 */
function loadPromptHistory(): string[] {
  try {
    const raw = window.localStorage.getItem(promptHistoryKey);
    const parsed: unknown = raw === null ? [] : JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter(item => typeof item === 'string').slice(0, promptHistoryLimit) : [];
  } catch {
    return [];
  }
}

function savePromptHistory(history: string[]) {
  try {
    window.localStorage.setItem(promptHistoryKey, JSON.stringify(history.slice(0, promptHistoryLimit)));
  } catch {
    // Storage unavailable — the panel still works, it just won't remember.
  }
}

let activeLabels: ToolbarLabels = defaultLabels;

/**
 * Allow the host to override toolbar text (called from the editor bootstrap).
 */
export function setAIToolbarLabels(labels: Partial<ToolbarLabels>) {
  activeLabels = { ...defaultLabels, ...labels };
}

interface AIToolbarState {
  busy: boolean;
  errorMessage?: string;
}

function isNonEmpty(value: string | undefined): value is string {
  return typeof value === 'string' && value.length > 0;
}

/**
 * CodeMirror extension that shows a floating toolbar with AI refactor actions
 * whenever the user has a non-empty text selection.
 */
export function aiSelectionToolbar() {
  return ViewPlugin.fromClass(class {
    private readonly dom: HTMLDivElement;
    private readonly statusEl: HTMLSpanElement;
    private readonly actionButtons: HTMLButtonElement[] = [];
    private readonly toneList: HTMLDivElement;
    private readonly toneToggle: HTMLButtonElement;
    private readonly personaList: HTMLDivElement;
    private readonly personaToggle: HTMLButtonElement;
    private readonly promptPanel: HTMLDivElement;
    private readonly promptToggle: HTMLButtonElement;
    private readonly promptInput: HTMLTextAreaElement;
    private readonly promptSourceRow: HTMLDivElement;
    private readonly promptChips: HTMLDivElement;
    private readonly promptRun: HTMLButtonElement;
    private personas: AIPersona[] | undefined;
    private personasLoading = false;
    private personaError: string | undefined;
    private knowledgeScope: string | undefined;
    private knowledgeConfig: AIKnowledgeConfig | undefined;
    private knowledgeLoading = false;
    private promptHistory: string[] = loadPromptHistory();
    private readonly state: AIToolbarState = { busy: false };
    private readonly boundOnKeyDown: (event: KeyboardEvent) => void;
    private manualPosition: { top: number; left: number } | undefined;
    private statusPinned = false;
    private wasFlipped = false;
    private activeDragCleanup: (() => void) | undefined;

    constructor(private readonly view: EditorView) {
      this.dom = document.createElement('div');
      this.dom.className = 'cm-md-aiToolbar';
      this.dom.setAttribute('aria-hidden', 'true');
      // Keep the editor selection when the toolbar is clicked — except for the
      // prompt field, which has to be able to take focus to be typed into.
      this.dom.addEventListener('mousedown', event => {
        if (!(event.target instanceof HTMLTextAreaElement || event.target instanceof HTMLSelectElement)) {
          event.preventDefault();
        }
      });
      this.statusEl = document.createElement('span');
      this.statusEl.className = 'cm-md-aiStatus';
      this.statusEl.style.display = 'none';
      this.toneList = document.createElement('div');
      this.toneToggle = document.createElement('button');
      this.personaList = document.createElement('div');
      this.personaToggle = document.createElement('button');
      this.promptPanel = document.createElement('div');
      this.promptToggle = document.createElement('button');
      this.promptInput = document.createElement('textarea');
      this.promptSourceRow = document.createElement('div');
      this.promptChips = document.createElement('div');
      this.promptRun = document.createElement('button');

      this.build();

      view.dom.appendChild(this.dom);

      this.boundOnKeyDown = this.onKeyDown.bind(this);
      document.addEventListener('keydown', this.boundOnKeyDown);
    }

    update(update: ViewUpdate) {
      if (update.selectionSet || update.docChanged || update.geometryChanged) {
        this.view.requestMeasure({
          read: () => { this.reposition(); },
        });
      }
    }

    destroy() {
      this.activeDragCleanup?.();
      document.removeEventListener('keydown', this.boundOnKeyDown);
      this.dom.remove();
    }

    private build() {
      const grip = document.createElement('div');
      grip.className = 'cm-md-aiGrip';
      grip.textContent = '⠿';
      grip.title = 'Drag to move';
      grip.addEventListener('mousedown', event => this.startDrag(event));
      this.dom.appendChild(grip);

      const addAction = (label: string, action: AIAction) => {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.textContent = label;
        btn.title = label;
        btn.addEventListener('click', () => {
          void this.runAction(action);
        });
        this.dom.appendChild(btn);
        this.actionButtons.push(btn);
      };

      addAction(activeLabels.improve, AIAction.improve);
      addAction(activeLabels.shorten, AIAction.shorten);
      addAction(activeLabels.expand, AIAction.expand);
      addAction(activeLabels.fixGrammar, AIAction.fixGrammar);

      const sep = document.createElement('div');
      sep.className = 'cm-md-aiSeparator';
      this.dom.appendChild(sep);

      this.buildPromptMenu();

      // Tone submenu
      const toneWrap = document.createElement('div');
      toneWrap.className = 'cm-md-aiToneMenu';
      this.toneToggle.type = 'button';
      this.toneToggle.textContent = `${activeLabels.tone} ▾`;
      this.toneToggle.title = activeLabels.tone;
      this.actionButtons.push(this.toneToggle);

      this.toneList.className = 'cm-md-aiToneList';
      this.toneList.style.display = 'none';

      const addTone = (label: string, action: AIAction) => {
        const tBtn = document.createElement('button');
        tBtn.type = 'button';
        tBtn.textContent = label;
        tBtn.addEventListener('click', () => {
          this.toneList.style.display = 'none';
          void this.runAction(action);
        });
        this.toneList.appendChild(tBtn);
      };
      addTone(activeLabels.toneProfessional, AIAction.toneProfessional);
      addTone(activeLabels.toneCasual, AIAction.toneCasual);
      addTone(activeLabels.toneFriendly, AIAction.toneFriendly);
      addTone(activeLabels.toneAcademic, AIAction.toneAcademic);

      this.toneToggle.addEventListener('click', () => {
        this.toneList.style.display = this.toneList.style.display === 'none' ? 'flex' : 'none';
      });

      toneWrap.appendChild(this.toneToggle);
      toneWrap.appendChild(this.toneList);
      this.dom.appendChild(toneWrap);

      // Persona submenu (nyxCore)
      const personaWrap = document.createElement('div');
      personaWrap.className = 'cm-md-aiPersonaMenu';
      this.personaToggle.type = 'button';
      this.personaToggle.textContent = `${activeLabels.persona} ▾`;
      this.personaToggle.title = activeLabels.persona;
      this.actionButtons.push(this.personaToggle);

      this.personaList.className = 'cm-md-aiPersonaList';
      this.personaList.style.display = 'none';

      this.personaToggle.addEventListener('click', () => {
        const visible = this.personaList.style.display !== 'none';
        this.personaList.style.display = visible ? 'none' : 'flex';
        if (!visible) {
          void this.loadPersonas();
        }
      });

      personaWrap.appendChild(this.personaToggle);
      personaWrap.appendChild(this.personaList);
      this.dom.appendChild(personaWrap);

      this.dom.appendChild(this.statusEl);
    }

    /**
     * The free-form instruction panel: source picker, the instruction itself,
     * and one-tap starters. The source sits above the field rather than behind a
     * menu, so it is never a surprise which knowledge an answer was — or was
     * not — grounded in.
     */
    private buildPromptMenu() {
      const wrap = document.createElement('div');
      wrap.className = 'cm-md-aiPromptMenu';

      this.promptToggle.type = 'button';
      this.promptToggle.textContent = `${activeLabels.prompt} ▾`;
      this.promptToggle.title = activeLabels.prompt;
      this.actionButtons.push(this.promptToggle);
      this.promptToggle.addEventListener('click', () => {
        if (this.promptPanel.style.display !== 'none') {
          this.promptPanel.style.display = 'none';
          return;
        }
        void this.openPrompt();
      });

      this.promptPanel.className = 'cm-md-aiPromptPanel';
      this.promptPanel.style.display = 'none';
      this.promptSourceRow.className = 'cm-md-aiSourceRow';
      this.promptChips.className = 'cm-md-aiPromptChips';

      this.promptInput.className = 'cm-md-aiPromptInput';
      this.promptInput.rows = 3;
      this.promptInput.placeholder = activeLabels.promptPlaceholder;
      this.promptInput.addEventListener('keydown', event => this.onPromptKeyDown(event));
      this.promptInput.addEventListener('input', () => {
        this.promptRun.disabled = this.promptInput.value.trim().length === 0;
      });

      const footer = document.createElement('div');
      footer.className = 'cm-md-aiPromptFooter';

      const hint = document.createElement('span');
      hint.className = 'cm-md-aiPromptHint';
      hint.textContent = activeLabels.promptHint;
      footer.appendChild(hint);

      this.promptRun.type = 'button';
      this.promptRun.className = 'cm-md-aiPromptRun';
      this.promptRun.textContent = activeLabels.promptRun;
      this.promptRun.disabled = true;
      this.promptRun.addEventListener('click', () => {
        void this.runPrompt();
      });
      footer.appendChild(this.promptRun);

      this.promptPanel.appendChild(this.promptSourceRow);
      this.promptPanel.appendChild(this.promptInput);
      this.promptPanel.appendChild(this.promptChips);
      this.promptPanel.appendChild(footer);

      wrap.appendChild(this.promptToggle);
      wrap.appendChild(this.promptPanel);
      this.dom.appendChild(wrap);
    }

    private onPromptKeyDown(event: KeyboardEvent) {
      // Escape closes the panel and hands focus back, rather than dismissing the
      // whole toolbar the way the document-level handler would.
      if (event.key === 'Escape') {
        event.stopPropagation();
        this.promptPanel.style.display = 'none';
        this.view.focus();
        return;
      }

      if (event.key === 'Enter' && !event.shiftKey) {
        event.preventDefault();
        void this.runPrompt();
      }
    }

    private async openPrompt() {
      this.toneList.style.display = 'none';
      this.personaList.style.display = 'none';
      this.promptPanel.style.display = 'flex';
      this.renderPromptPanel();
      this.promptInput.focus();

      await this.loadKnowledgeConfig();
      this.renderPromptPanel();
    }

    private renderPromptPanel() {
      this.renderSourceRow(this.promptSourceRow);
      this.renderPromptChips();
      this.promptRun.disabled = this.state.busy || this.promptInput.value.trim().length === 0;
    }

    /** Recent instructions once there are any, worked examples until then. */
    private renderPromptChips() {
      this.promptChips.replaceChildren();

      const hasHistory = this.promptHistory.length > 0;
      const entries = hasHistory ? this.promptHistory : promptExamples;

      const title = document.createElement('span');
      title.className = 'cm-md-aiPromptChipsTitle';
      title.textContent = hasHistory ? activeLabels.promptRecentTitle : activeLabels.promptExamplesTitle;
      this.promptChips.appendChild(title);

      for (const entry of entries) {
        const chip = document.createElement('button');
        chip.type = 'button';
        chip.className = 'cm-md-aiPromptChip';
        chip.textContent = entry;
        chip.title = entry;
        chip.addEventListener('click', () => {
          this.promptInput.value = entry;
          this.promptRun.disabled = false;
          this.promptInput.focus();
        });
        this.promptChips.appendChild(chip);
      }
    }

    private async runPrompt() {
      const instruction = this.promptInput.value.trim();
      if (instruction.length === 0) {
        return;
      }

      const { sel, selectedText, context } = this.selectionContext();
      if (sel.empty) {
        return;
      }

      this.rememberPrompt(instruction);
      this.promptPanel.style.display = 'none';

      await this.runRewrite(sel, () => window.nativeModules.ai.refactorWithPrompt({
        prompt: instruction,
        selection: selectedText,
        context,
        knowledgeSource: this.knowledgeScope ?? 'off',
      }));
    }

    private rememberPrompt(instruction: string) {
      this.promptHistory = [instruction, ...this.promptHistory.filter(item => item !== instruction)]
        .slice(0, promptHistoryLimit);
      savePromptHistory(this.promptHistory);
    }

    /** Loads the knowledge configuration once; safe to await from anywhere. */
    private async loadKnowledgeConfig() {
      if (this.knowledgeConfig !== undefined || this.knowledgeLoading) {
        return;
      }

      this.knowledgeLoading = true;
      try {
        const raw = await window.nativeModules.ai.getKnowledgeConfig();
        this.knowledgeConfig = typeof raw === 'string' ? JSON.parse(raw) as AIKnowledgeConfig : raw;
      } catch {
        this.knowledgeConfig = { availableScopes: ['off'], defaultScope: 'off' };
      } finally {
        this.knowledgeLoading = false;
      }

      if (this.knowledgeScope === undefined) {
        this.knowledgeScope = this.knowledgeConfig.defaultSourceId ?? this.knowledgeConfig.defaultScope ?? 'off';
      }
    }

    private async loadPersonas() {
      if (this.personas !== undefined || this.personasLoading) {
        return;
      }

      this.personasLoading = true;
      this.renderPersonaList();

      try {
        const [rawPersonas] = await Promise.all([
          window.nativeModules.ai.listPersonas(),
          this.loadKnowledgeConfig(),
        ]);

        let response: AIPersonaListResponse;
        try {
          response = typeof rawPersonas === 'string' ? JSON.parse(rawPersonas) as AIPersonaListResponse : rawPersonas;
        } catch {
          response = { error: 'Invalid persona response payload.' };
        }

        if (isNonEmpty(response.error)) {
          this.personas = [];
          this.personaError = response.error;
        } else {
          this.personas = response.personas ?? [];
          this.personaError = undefined;
        }
      } catch (err) {
        this.personas = [];
        this.personaError = err instanceof Error ? err.message : String(err);
      } finally {
        this.personasLoading = false;
        this.renderPersonaList();
      }
    }

    private renderPersonaList() {
      this.personaList.replaceChildren();

      const scopeRow = document.createElement('div');
      scopeRow.className = 'cm-md-aiSourceRow';
      this.renderSourceRow(scopeRow);
      this.personaList.appendChild(scopeRow);

      if (this.personasLoading) {
        const info = document.createElement('span');
        info.className = 'cm-md-aiPersonaInfo';
        info.textContent = activeLabels.personaLoading;
        this.personaList.appendChild(info);
        return;
      }

      if (this.personas === undefined || this.personas.length === 0) {
        const info = document.createElement('span');
        info.className = 'cm-md-aiPersonaInfo';
        info.textContent = isNonEmpty(this.personaError) ? this.personaError : activeLabels.noPersonas;
        this.personaList.appendChild(info);
        return;
      }

      // Group Persona Studio personas by circle; MCP personas have no group.
      const grouped = new Map<string, AIPersona[]>();
      for (const persona of this.personas) {
        const key = persona.circleName ?? '';
        const list = grouped.get(key) ?? [];
        list.push(persona);
        grouped.set(key, list);
      }

      for (const [circleName, personas] of grouped) {
        if (circleName.length > 0 && grouped.size > 1) {
          const header = document.createElement('span');
          header.className = 'cm-md-aiPersonaGroup';
          header.textContent = circleName;
          this.personaList.appendChild(header);
        }

        for (const persona of personas) {
          const pBtn = document.createElement('button');
          pBtn.type = 'button';
          pBtn.textContent = persona.name;
          if (isNonEmpty(persona.description)) {
            pBtn.title = persona.description;
          }
          pBtn.addEventListener('click', () => {
            this.personaList.style.display = 'none';
            void this.runPersona(persona);
          });
          this.personaList.appendChild(pBtn);
        }
      }
    }

    /**
     * Knowledge source picker, shared by the persona menu and the prompt panel
     * so both always agree on what the next rewrite will be grounded in.
     *
     * A list of named places beats a row of scope words: "Compliance-Axiom" is
     * answerable, "Global" is a guess about someone else's configuration.
     */
    private renderSourceRow(container: HTMLElement) {
      container.replaceChildren();

      const title = document.createElement('span');
      title.className = 'cm-md-aiPersonaInfo';
      title.textContent = activeLabels.knowledgeTitle;
      container.appendChild(title);

      const select = document.createElement('select');
      select.className = 'cm-md-aiSourceSelect';
      select.disabled = this.knowledgeLoading;
      select.title = 'Where the AI may look things up for this rewrite';

      const current = this.knowledgeScope
        ?? this.knowledgeConfig?.defaultSourceId
        ?? this.knowledgeConfig?.defaultScope
        ?? 'off';

      for (const source of this.availableSources()) {
        const option = document.createElement('option');
        option.value = source.id;
        option.textContent = source.name;
        option.selected = source.id === current;
        select.appendChild(option);
      }

      select.addEventListener('change', () => {
        this.knowledgeScope = select.value;
      });

      container.appendChild(select);
    }

    /**
     * Sources as the native side reports them, falling back to names derived
     * from the legacy scope list when a host only supplies that.
     */
    private availableSources(): AIKnowledgeSource[] {
      const provided = this.knowledgeConfig?.sources;
      if (provided !== undefined && provided.length > 0) {
        return provided;
      }

      const names: Record<string, string> = {
        off: activeLabels.scopeOff,
        project: activeLabels.scopeProject,
        global: activeLabels.scopeGlobal,
        all: activeLabels.scopeAll,
      };

      const scopes = this.knowledgeConfig?.availableScopes ?? ['off'];
      return scopes.map(scope => ({ id: scope, name: names[scope] ?? scope, kind: scope }));
    }

    private onKeyDown(event: KeyboardEvent): void {
      if (event.key === 'Escape' && this.dom.getAttribute('aria-hidden') === 'false') {
        this.hide();
      }
    }

    private startDrag(event: MouseEvent) {
      event.preventDefault();
      event.stopPropagation();

      const toolbarRect = this.dom.getBoundingClientRect();
      const editorRect = this.view.dom.getBoundingClientRect();
      const origin = {
        top: toolbarRect.top - editorRect.top,
        left: toolbarRect.left - editorRect.left,
      };
      const startX = event.clientX;
      const startY = event.clientY;

      const onMove = (move: MouseEvent) => {
        const rect = this.view.dom.getBoundingClientRect();
        const pos = clampPosition(
          { top: origin.top + (move.clientY - startY), left: origin.left + (move.clientX - startX) },
          { width: toolbarRect.width, height: toolbarRect.height },
          { width: rect.width, height: rect.height },
        );
        this.manualPosition = pos;
        this.dom.style.top = `${pos.top}px`;
        this.dom.style.left = `${pos.left}px`;
      };

      const cleanup = () => {
        document.removeEventListener('mousemove', onMove);
        document.removeEventListener('mouseup', onUp);
        this.activeDragCleanup = undefined;
      };
      const onUp = () => cleanup();

      document.addEventListener('mousemove', onMove);
      document.addEventListener('mouseup', onUp);
      this.activeDragCleanup = cleanup;
    }

    private reposition() {
      // Don't compete with macOS Writing Tools.
      if (isWritingToolsActive()) {
        this.hide();
        return;
      }

      const sel = this.view.state.selection.main;
      if (sel.empty || this.state.busy) {
        if (!this.state.busy) {
          this.hide();
        }
        return;
      }

      const startPos = Math.min(sel.from, sel.to);
      const endPos = Math.max(sel.from, sel.to);
      const selStart = this.view.coordsAtPos(startPos);
      const selEnd = this.view.coordsAtPos(endPos);
      if (selStart === null || selEnd === null) {
        this.hide();
        return;
      }

      this.applyTheme();
      this.dom.style.position = 'absolute';
      this.dom.style.zIndex = '550';
      this.dom.setAttribute('aria-hidden', 'false');

      const editorRect = this.view.dom.getBoundingClientRect();
      const toolbarRect = this.dom.getBoundingClientRect();
      const toolbarSize = { width: toolbarRect.width, height: toolbarRect.height };

      if (this.manualPosition !== undefined) {
        // The user dragged the toolbar — keep their position, re-clamped.
        const pos = clampPosition(this.manualPosition, toolbarSize, {
          width: editorRect.width, height: editorRect.height,
        });
        this.dom.style.top = `${pos.top}px`;
        this.dom.style.left = `${pos.left}px`;
      } else {
        const placement = computeToolbarPosition({
          selStart, selEnd, toolbar: toolbarSize, editor: editorRect, wasFlipped: this.wasFlipped,
        });
        this.wasFlipped = placement.flipped;
        this.dom.style.top = `${placement.top}px`;
        this.dom.style.left = `${placement.left}px`;
      }

      // Reset transient status after the user moves on. A warning raised by the
      // rewrite that just landed has to survive the reposition its own document
      // change triggers, or it would never be readable.
      if (this.statusPinned) {
        this.statusPinned = false;
      } else if (isNonEmpty(this.state.errorMessage)) {
        this.clearStatus();
      }
    }

    /** Sync toolbar colors with the active editor theme (not just OS appearance). */
    private applyTheme() {
      const colors = globalState.colors;
      if (colors === undefined) {
        return; // CSS falls back to system colors.
      }
      this.dom.style.setProperty('--md-ai-bg', colors.background);
      this.dom.style.setProperty('--md-ai-fg', colors.text);
      this.dom.style.setProperty('--md-ai-accent', colors.accent);
    }

    private hide() {
      this.dom.setAttribute('aria-hidden', 'true');
      this.toneList.style.display = 'none';
      this.personaList.style.display = 'none';
      this.promptPanel.style.display = 'none';
      this.statusPinned = false;
      this.clearStatus();
      this.manualPosition = undefined;
      this.wasFlipped = false;
    }

    private setBusy(busy: boolean, label = activeLabels.loading) {
      this.state.busy = busy;
      this.actionButtons.forEach(b => { b.disabled = busy; });
      this.promptRun.disabled = busy || this.promptInput.value.trim().length === 0;
      if (busy) {
        this.statusEl.textContent = label;
        this.statusEl.className = 'cm-md-aiStatus';
        this.statusEl.style.display = '';
      } else {
        this.clearStatus();
      }
    }

    private setError(message: string) {
      this.statusEl.textContent = message;
      this.statusEl.className = 'cm-md-aiError';
      this.statusEl.style.display = '';
      this.state.errorMessage = message;
    }

    /**
     * Non-fatal note shown beside a rewrite that did land — typically that the
     * chosen knowledge source could not be consulted. Kept visible instead of
     * dismissing the toolbar, because a rewrite the user believes is grounded
     * and one that silently is not are indistinguishable in the document.
     */
    private setWarning(message: string) {
      this.statusEl.textContent = message;
      this.statusEl.className = 'cm-md-aiWarning';
      this.statusEl.style.display = '';
      this.state.errorMessage = message;
      this.statusPinned = true;
    }

    private clearStatus() {
      this.statusEl.style.display = 'none';
      this.statusEl.textContent = '';
      this.state.errorMessage = undefined;
    }

    /** Selection text plus a small surrounding window so the model can match style. */
    private selectionContext() {
      const sel = this.view.state.selection.main;
      const selectedText = this.view.state.sliceDoc(sel.from, sel.to);
      const ctxFrom = Math.max(0, sel.from - 600);
      const ctxTo = Math.min(this.view.state.doc.length, sel.to + 200);
      const context = this.view.state.sliceDoc(ctxFrom, ctxTo);
      return { sel, selectedText, context };
    }

    private async runAction(action: AIAction) {
      const { sel, selectedText, context } = this.selectionContext();
      if (sel.empty) {
        return;
      }

      await this.runRewrite(sel, () => window.nativeModules.ai.refactor({
        action,
        selection: selectedText,
        context,
      }));
    }

    private async runPersona(persona: AIPersona) {
      const { sel, selectedText, context } = this.selectionContext();
      if (sel.empty) {
        return;
      }

      await this.runRewrite(sel, () => window.nativeModules.ai.refactorWithPersona({
        personaID: persona.id,
        personaName: persona.name,
        circleID: persona.circleId,
        selection: selectedText,
        context,
        knowledgeScope: this.knowledgeScope ?? 'off',
      }));
    }

    /** Shared busy/parse/replace handling for any rewrite source. */
    private async runRewrite(
      sel: { from: number; to: number },
      invoke: () => Promise<string>,
    ) {
      this.setBusy(true);
      try {
        const raw = await invoke();

        let response: AIRefactorResponse;
        try {
          response = typeof raw === 'string' ? JSON.parse(raw) as AIRefactorResponse : raw;
        } catch {
          response = { error: 'Invalid AI response payload.' };
        }

        if (isNonEmpty(response.error)) {
          this.setBusy(false);
          this.setError(response.error);
          return;
        }

        if (!isNonEmpty(response.result)) {
          this.setBusy(false);
          this.setError('No response');
          return;
        }

        const replacement = response.result;
        this.view.dispatch({
          changes: { from: sel.from, to: sel.to, insert: replacement },
          selection: EditorSelection.range(sel.from, sel.from + replacement.length),
          userEvent: 'input.aiRefactor',
        });

        this.setBusy(false);
        if (isNonEmpty(response.warning)) {
          this.setWarning(response.warning);
        } else {
          this.hide();
        }
      } catch (err) {
        this.setBusy(false);
        this.setError(err instanceof Error ? err.message : String(err));
      }
    }
  });
}
