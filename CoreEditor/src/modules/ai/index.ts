import { EditorView, ViewPlugin, ViewUpdate } from '@codemirror/view';
import { EditorSelection } from '@codemirror/state';
import { AIAction } from '../../bridge/native/ai';
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
  loading: string;
  notConfigured: string;
}

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
  loading: 'Thinking…',
  notConfigured: 'Configure AI in Settings',
};

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
    private readonly state: AIToolbarState = { busy: false };
    private readonly boundOnKeyDown: (event: KeyboardEvent) => void;

    constructor(private readonly view: EditorView) {
      this.dom = document.createElement('div');
      this.dom.className = 'cm-md-aiToolbar';
      this.dom.setAttribute('aria-hidden', 'true');
      this.dom.addEventListener('mousedown', e => e.preventDefault()); // keep editor selection
      this.statusEl = document.createElement('span');
      this.statusEl.className = 'cm-md-aiStatus';
      this.statusEl.style.display = 'none';
      this.toneList = document.createElement('div');
      this.toneToggle = document.createElement('button');

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
      document.removeEventListener('keydown', this.boundOnKeyDown);
      this.dom.remove();
    }

    private build() {
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

      this.dom.appendChild(this.statusEl);
    }

    private onKeyDown(event: KeyboardEvent): void {
      if (event.key === 'Escape' && this.dom.getAttribute('aria-hidden') === 'false') {
        this.hide();
      }
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

      // Anchor at the start of the (visual) selection.
      const anchorPos = Math.min(sel.from, sel.to);
      const coords = this.view.coordsAtPos(anchorPos);
      if (coords === null) {
        this.hide();
        return;
      }

      const editorRect = this.view.dom.getBoundingClientRect();
      const top = coords.top - editorRect.top - 44; // toolbar above the line
      const left = coords.left - editorRect.left;

      this.dom.style.position = 'absolute';
      this.dom.style.top = `${Math.max(top, 0)}px`;
      this.dom.style.left = `${Math.max(left, 0)}px`;
      this.dom.style.zIndex = '20';
      this.dom.setAttribute('aria-hidden', 'false');

      // Reset transient error after the user moves on.
      if (isNonEmpty(this.state.errorMessage)) {
        this.clearStatus();
      }
    }

    private hide() {
      this.dom.setAttribute('aria-hidden', 'true');
      this.toneList.style.display = 'none';
      this.clearStatus();
    }

    private setBusy(busy: boolean, label = activeLabels.loading) {
      this.state.busy = busy;
      this.actionButtons.forEach(b => { b.disabled = busy; });
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

    private clearStatus() {
      this.statusEl.style.display = 'none';
      this.statusEl.textContent = '';
      this.state.errorMessage = undefined;
    }

    private async runAction(action: AIAction) {
      const sel = this.view.state.selection.main;
      if (sel.empty) {
        return;
      }

      const selectedText = this.view.state.sliceDoc(sel.from, sel.to);

      // Provide a small surrounding context window so the model can match style.
      const ctxFrom = Math.max(0, sel.from - 600);
      const ctxTo = Math.min(this.view.state.doc.length, sel.to + 200);
      const context = this.view.state.sliceDoc(ctxFrom, ctxTo);

      this.setBusy(true);
      try {
        const raw = await window.nativeModules.ai.refactor({
          action,
          selection: selectedText,
          context,
        });

        let response: { result?: string; error?: string };
        try {
          response = typeof raw === 'string' ? JSON.parse(raw) as { result?: string; error?: string } : raw;
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
        this.hide();
      } catch (err) {
        this.setBusy(false);
        this.setError(err instanceof Error ? err.message : String(err));
      }
    }
  });
}
