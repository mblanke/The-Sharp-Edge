import { describe, expect, it } from 'vitest';
import { renderMd } from './md';

describe('renderMd', () => {
  it('escapes HTML before anything else', () => {
    expect(renderMd('<script>alert(1)</script> & "q"')).toBe(
      '<p>&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;q&quot;</p>'
    );
  });

  it('renders paragraphs, bold, code and citations', () => {
    expect(renderMd('Sear the **beef** hard [1].\n\nThen `deglaze`.')).toBe(
      '<p>Sear the <strong>beef</strong> hard <sup class="cite">[1]</sup>.</p><p>Then <code>deglaze</code>.</p>'
    );
  });

  it('turns bullets and numbers into lists and closes them', () => {
    expect(renderMd('Steps:\n- brown\n- braise\n\n1. rest\n2) slice')).toBe(
      '<p>Steps:</p><ul><li>brown</li><li>braise</li></ul><ol><li>rest</li><li>slice</li></ol>'
    );
  });

  it('keeps single line breaks inside a paragraph and treats headings as bold lines', () => {
    expect(renderMd('## Method\nline one\nline two')).toBe('<p><strong>Method</strong></p><p>line one<br>line two</p>');
  });

  it('does not mistake a multiplication sign for emphasis', () => {
    expect(renderMd('2 * 3 * 4')).toBe('<p>2 * 3 * 4</p>');
    expect(renderMd('a *word* here')).toBe('<p>a <em>word</em> here</p>');
  });
});
