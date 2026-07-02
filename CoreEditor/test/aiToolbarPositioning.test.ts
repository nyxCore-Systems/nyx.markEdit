import { clampPosition, computeToolbarPosition, toolbarGap } from '../src/modules/ai/positioning';

const editor = { top: 0, bottom: 600, left: 0, right: 800 };
const toolbar = { width: 400, height: 32 };
const line = (top: number, left = 100) => ({ top, bottom: top + 20, left, right: left + 50 });

describe('computeToolbarPosition', () => {
  test('places the toolbar above the selection when there is room', () => {
    const result = computeToolbarPosition({
      selStart: line(300), selEnd: line(340), toolbar, editor, wasFlipped: false,
    });
    expect(result.flipped).toBe(false);
    expect(result.top).toBe(300 - toolbar.height - toolbarGap);
    expect(result.left).toBe(100);
  });

  test('flips below the selection end when there is no room above', () => {
    const result = computeToolbarPosition({
      selStart: line(10), selEnd: line(30), toolbar, editor, wasFlipped: false,
    });
    expect(result.flipped).toBe(true);
    expect(result.top).toBe(50 + toolbarGap); // selEnd.bottom (30 + 20) + gap
  });

  test('stays flipped while below still fits (sticky flag)', () => {
    const result = computeToolbarPosition({
      selStart: line(300), selEnd: line(340), toolbar, editor, wasFlipped: true,
    });
    expect(result.flipped).toBe(true);
    expect(result.top).toBe(360 + toolbarGap);
  });

  test('un-flips when below no longer fits', () => {
    const result = computeToolbarPosition({
      selStart: line(500), selEnd: line(590), toolbar, editor, wasFlipped: true,
    });
    expect(result.flipped).toBe(false);
    expect(result.top).toBe(500 - toolbar.height - toolbarGap);
  });

  test('clamps to the right edge', () => {
    const result = computeToolbarPosition({
      selStart: line(300, 700), selEnd: line(340, 700), toolbar, editor, wasFlipped: false,
    });
    expect(result.left).toBe(800 - toolbar.width); // 400
  });

  test('clamps within the editor when neither side fits', () => {
    const smallEditor = { top: 0, bottom: 40, left: 0, right: 800 };
    const result = computeToolbarPosition({
      selStart: line(5), selEnd: line(15), toolbar, editor: smallEditor, wasFlipped: false,
    });
    expect(result.flipped).toBe(false);
    expect(result.top).toBe(0); // negative above-position clamps to the top edge
  });
});

describe('clampPosition', () => {
  test('clamps negative and overflowing coordinates', () => {
    expect(clampPosition({ top: -10, left: 900 }, toolbar, { width: 800, height: 600 }))
      .toEqual({ top: 0, left: 400 });
  });

  test('pins to 0 when the toolbar is larger than the editor', () => {
    expect(clampPosition({ top: 50, left: 50 }, { width: 900, height: 700 }, { width: 800, height: 600 }))
      .toEqual({ top: 0, left: 0 });
  });
});
