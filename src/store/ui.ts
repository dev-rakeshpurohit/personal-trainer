import { create } from 'zustand';

export interface Toast {
  id: number;
  message: string;
  tone?: 'default' | 'success' | 'pr';
  undo?: () => void | Promise<void>;
}

interface UIState {
  toasts: Toast[];
  needRefresh: boolean;
  updateSW?: (reload?: boolean) => Promise<void>;
  flash: number;
  toast: (message: string, opts?: Omit<Toast, 'id' | 'message'>) => void;
  dismiss: (id: number) => void;
  setNeedRefresh: (v: boolean, fn?: (reload?: boolean) => Promise<void>) => void;
  triggerFlash: () => void;
}

let seq = 1;

export const useUI = create<UIState>((set) => ({
  toasts: [],
  needRefresh: false,
  flash: 0,
  toast: (message, opts) => {
    const id = seq++;
    set((s) => ({ toasts: [...s.toasts.slice(-2), { id, message, ...opts }] }));
    setTimeout(() => set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) })), opts?.undo ? 5000 : 3000);
  },
  dismiss: (id) => set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) })),
  setNeedRefresh: (v, fn) => set({ needRefresh: v, updateSW: fn }),
  triggerFlash: () => set((s) => ({ flash: s.flash + 1 })),
}));
