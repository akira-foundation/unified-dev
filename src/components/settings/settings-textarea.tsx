interface SettingsTextareaProps {
  label: string;
  description?: string;
  defaultValue?: string;
}

export function SettingsTextarea({ label, description, defaultValue }: SettingsTextareaProps) {
  return (
    <div className="flex flex-col gap-3 px-4 py-6 transition-colors hover:bg-zinc-50 dark:hover:bg-zinc-900/40 border-b border-zinc-100 dark:border-zinc-800/50 last:border-0">
      <div className="flex flex-col gap-1">
        <p className="text-sm font-medium text-zinc-900 dark:text-white">{label}</p>
      </div>
      <textarea
        className="w-full h-48 bg-zinc-50 dark:bg-black/20 border border-zinc-200 dark:border-white/5 rounded-md text-zinc-600 dark:text-zinc-400 font-mono text-[13px] p-4 focus:outline-none focus:border-purple-500 transition-colors custom-scrollbar"
        defaultValue={defaultValue}
      />
      {description && <p className="text-xs text-zinc-500 dark:text-zinc-400 leading-relaxed">{description}</p>}
    </div>
  );
}
