import type { Config } from 'tailwindcss';
export default {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        ink: '#06090C', panel: '#0B1117', raised: '#101820', rule: '#18232D', rule2: '#243341',
        fg: '#E4ECF1', muted: '#8796A3', faint: '#5A6976',
        signal: '#3ED6C5', memory: '#6E9BFF', challenge: '#F0B54A', veto: '#FF7A6B', ok: '#7FD88F',
      },
      fontFamily: {
        sans: ['"Schibsted Grotesk Variable"', 'system-ui', 'sans-serif'],
        mono: ['"IBM Plex Mono"', 'ui-monospace', 'monospace'],
      },
      maxWidth: { prose: '68ch' },
    },
  },
  plugins: [],
} satisfies Config;
