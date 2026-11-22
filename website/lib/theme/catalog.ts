/**
 * Curated themes. Sourced from livlign/ccthemes (MIT, https://github.com/livlign/ccthemes): the accent (`claude`), status colours
 * (`success`, `error`, `warning`), `planMode` (info) and `text` of each Claude Code theme file. Claude Code themes colour the semantic UI
 * only and carry NO background, so the page/sidebar/card surfaces here are each palette's published background colours (Nord, Dracula,
 * Catppuccin, GitHub, Solarized, Rosé Pine, Tokyo Night, One Dark, Everforest, Gruvbox), chosen by hand. Secondary and muted text are derived
 * (derive.ts), and the derivation adjusts anything that would be hard to read.
 *
 * To add a theme: copy a Claude Code theme JSON's colours here, add the palette's background(s), then run `npm test` (every theme is checked
 * for text contrast). See docs/Architecture/theme-curation.md.
 */
import type { ThemeDef } from './themes';

const SRC = 'https://github.com/livlign/ccthemes';
const t = (id: string, label: string, inputs: ThemeDef['inputs']): ThemeDef => ({ v: 1, id, label, inputs, source: SRC });

export const CURATED_THEMES: ThemeDef[] = [
  t('nord', 'Nord', {
    dark: { accent: '#81a1c1', danger: '#bf616a', success: '#a3be8c', warning: '#ebcb8b', pro: '#88c0d0', 'surface-0': '#2e3440', 'surface-2': '#3b4252', 'text-primary': '#d8dee9' },
  }),
  t('dracula', 'Dracula', {
    dark: { accent: '#bd93f9', danger: '#ff5555', success: '#50fa7b', warning: '#f1fa8c', pro: '#8be9fd', 'surface-0': '#282a36', 'surface-2': '#343746', 'text-primary': '#f8f8f2' },
  }),
  t('catppuccin', 'Catppuccin', {
    light: { accent: '#145ff5', danger: '#d20f39', success: '#40a02b', warning: '#df8e1d', pro: '#179299', 'surface-0': '#eff1f5', 'surface-1': '#e6e9ef', 'surface-2': '#ffffff', 'text-primary': '#4c4f69' },
    dark: { accent: '#89b4fa', danger: '#f38ba8', success: '#a6e3a1', warning: '#f9e2af', pro: '#94e2d5', 'surface-0': '#1e1e2e', 'surface-1': '#181825', 'surface-2': '#313244', 'text-primary': '#cdd6f4' },
  }),
  t('github', 'GitHub', {
    light: { accent: '#0366d6', danger: '#d73a49', success: '#28a745', warning: '#dbab09', pro: '#1b7c83', 'surface-0': '#f6f8fa', 'surface-1': '#eaeef2', 'surface-2': '#ffffff', 'text-primary': '#24292f' },
    dark: { accent: '#58a6ff', danger: '#ff7b72', success: '#3fb950', warning: '#d29922', pro: '#39c5cf', 'surface-0': '#0d1117', 'surface-1': '#010409', 'surface-2': '#161b22', 'text-primary': '#c9d1d9' },
  }),
  t('solarized', 'Solarized', {
    light: { accent: '#2074af', danger: '#dc322f', success: '#859900', warning: '#b58900', pro: '#2aa198', 'surface-0': '#fdf6e3', 'surface-1': '#eee8d5', 'surface-2': '#fffaf0', 'text-primary': '#657b83' },
    dark: { accent: '#3295da', danger: '#dc322f', success: '#859900', warning: '#b58900', pro: '#2aa198', 'surface-0': '#002b36', 'surface-1': '#00212b', 'surface-2': '#073642', 'text-primary': '#839496' },
  }),
  t('rose-pine', 'Rosé Pine', {
    light: { accent: '#44757e', danger: '#b4637a', success: '#286983', warning: '#ea9d34', pro: '#d7827e', 'surface-0': '#faf4ed', 'surface-1': '#f2e9e1', 'surface-2': '#fffaf3', 'text-primary': '#575279' },
    dark: { accent: '#9ccfd8', danger: '#eb6f92', success: '#31748f', warning: '#f6c177', pro: '#ebbcba', 'surface-0': '#191724', 'surface-1': '#16141f', 'surface-2': '#1f1d2e', 'text-primary': '#e0def4' },
  }),
  t('tokyo-night', 'Tokyo Night', {
    dark: { accent: '#7aa2f7', danger: '#f7768e', success: '#9ece6a', warning: '#e0af68', pro: '#7dcfff', 'surface-0': '#1a1b26', 'surface-1': '#16161e', 'surface-2': '#24283b', 'text-primary': '#c0caf5' },
  }),
  t('one-dark', 'One Dark', {
    dark: { accent: '#61afef', danger: '#e06c75', success: '#98c379', warning: '#e5c07b', pro: '#56b6c2', 'surface-0': '#282c34', 'surface-1': '#21252b', 'surface-2': '#2c313c', 'text-primary': '#abb2bf' },
  }),
  t('everforest', 'Everforest', {
    dark: { accent: '#7fbbb3', danger: '#e67e80', success: '#a7c080', warning: '#dbbc7f', pro: '#83c092', 'surface-0': '#2d353b', 'surface-1': '#272e33', 'surface-2': '#343f44', 'text-primary': '#d3c6aa' },
  }),
  t('gruvbox', 'Gruvbox', {
    dark: { accent: '#83a598', danger: '#cc241d', success: '#98971a', warning: '#d79921', pro: '#689d6a', 'surface-0': '#282828', 'surface-1': '#1d2021', 'surface-2': '#3c3836', 'text-primary': '#ebdbb2' },
  }),
];
