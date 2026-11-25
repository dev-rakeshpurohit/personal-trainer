import type { Config } from 'tailwindcss';

const v = (name: string) => `rgb(var(--${name}) / <alpha-value>)`;

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        bg: v('bg'),
        surface: v('surface'),
        surface2: v('surface2'),
        line: v('line'),
        text: v('text'),
        muted: v('muted'),
        primary: v('primary'),
        'primary-ink': v('primary-ink'),
        'on-primary': v('on-primary'),
        success: v('success'),
        warning: v('warning'),
        danger: v('danger'),
        info: v('info'),
      },
      fontFamily: { sans: ['"Inter Variable"', 'Inter', 'system-ui', '-apple-system', 'sans-serif'] },
      fontSize: {
        caption: ['0.8125rem', { lineHeight: '1.1rem' }],
        body: ['1rem', { lineHeight: '1.45rem' }],
        title: ['1.375rem', { lineHeight: '1.75rem', fontWeight: '700' }],
        display: ['2.5rem', { lineHeight: '3rem', fontWeight: '700' }],
        hero: ['4.5rem', { lineHeight: '1', fontWeight: '700' }],
      },
      borderRadius: { card: '16px', btn: '12px' },
      minHeight: { tap: '48px' },
      minWidth: { tap: '48px' },
      transitionTimingFunction: { out: 'cubic-bezier(0.16, 1, 0.3, 1)' },
      keyframes: {
        'slide-up': { from: { transform: 'translateY(100%)' }, to: { transform: 'translateY(0)' } },
        'fade-in': { from: { opacity: '0' }, to: { opacity: '1' } },
        'pop': { '0%': { transform: 'scale(0.96)', opacity: '0' }, '100%': { transform: 'scale(1)', opacity: '1' } },
        shimmer: { '0%': { backgroundPosition: '-200% 0' }, '100%': { backgroundPosition: '200% 0' } },
        flash: { '0%,100%': { opacity: '0' }, '20%,60%': { opacity: '1' } },
      },
      animation: {
        'slide-up': 'slide-up 250ms cubic-bezier(0.16, 1, 0.3, 1)',
        'fade-in': 'fade-in 200ms ease-out',
        pop: 'pop 220ms cubic-bezier(0.16, 1, 0.3, 1)',
        shimmer: 'shimmer 600ms ease-out',
        flash: 'flash 1200ms ease-out',
      },
    },
  },
  plugins: [],
} satisfies Config;
