export interface Rect { top: number; bottom: number; left: number; right: number }
export interface Size { width: number; height: number }
export interface Point { top: number; left: number }

/** Gap between the toolbar and the selection line, in pixels. */
export const toolbarGap = 8;

/**
 * Clamp a candidate position so the toolbar stays fully inside the editor.
 */
export function clampPosition(pos: Point, toolbar: Size, editor: Size): Point {
  const maxLeft = Math.max(0, editor.width - toolbar.width);
  const maxTop = Math.max(0, editor.height - toolbar.height);
  return {
    top: Math.min(Math.max(pos.top, 0), maxTop),
    left: Math.min(Math.max(pos.left, 0), maxLeft),
  };
}

/**
 * Compute where the floating AI toolbar should sit relative to the editor.
 *
 * Prefers sitting above the selection start; flips below the selection end
 * when there is not enough room above. The flip is sticky (wasFlipped) so the
 * toolbar does not flutter between positions while the selection grows.
 */
export function computeToolbarPosition(args: {
  selStart: Rect;
  selEnd: Rect;
  toolbar: Size;
  editor: Rect;
  wasFlipped: boolean;
}): { top: number; left: number; flipped: boolean } {
  const { selStart, selEnd, toolbar, editor, wasFlipped } = args;
  const editorSize = { width: editor.right - editor.left, height: editor.bottom - editor.top };

  const aboveTop = selStart.top - editor.top - toolbar.height - toolbarGap;
  const belowTop = selEnd.bottom - editor.top + toolbarGap;
  const fitsAbove = aboveTop >= 0;
  const fitsBelow = belowTop + toolbar.height <= editorSize.height;

  const flipped = wasFlipped ? fitsBelow : (!fitsAbove && fitsBelow);
  const top = flipped ? belowTop : aboveTop;
  const left = selStart.left - editor.left;
  return { ...clampPosition({ top, left }, toolbar, editorSize), flipped };
}
