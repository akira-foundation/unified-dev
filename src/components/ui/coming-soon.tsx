import { cn } from "@/lib/utils";

interface ComingSoonProps {
  children: React.ReactNode;
  className?: string;
}

export function ComingSoon({ children, className }: ComingSoonProps) {
  return (
    <div className={cn("relative", className)}>
      <div className="pointer-events-none select-none opacity-40">
        {children}
      </div>
      <div className="absolute inset-0 flex items-center justify-end pr-4">
        <span className="inline-flex items-center rounded-full border border-zinc-700 bg-zinc-900/80 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-widest text-zinc-400 backdrop-blur-sm">
          Coming Soon
        </span>
      </div>
    </div>
  );
}
