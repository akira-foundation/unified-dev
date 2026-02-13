import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center justify-center rounded-full border px-2.5 py-0.5 text-xs font-bold w-fit whitespace-nowrap shrink-0 [&>svg]:size-3 gap-1.5 [&>svg]:pointer-events-none transition-[color,box-shadow,background-color] overflow-hidden",
  {
    variants: {
      variant: {
        default: "border-transparent bg-purple-600 text-white hover:bg-purple-700 shadow-sm",
        secondary:
          "border-transparent bg-zinc-100 text-zinc-900 hover:bg-zinc-200 dark:bg-zinc-800 dark:text-zinc-50 dark:hover:bg-zinc-700",
        destructive: "border-transparent bg-red-600 text-white hover:bg-red-700 shadow-sm",
        outline:
          "text-zinc-950 dark:text-zinc-50 border-zinc-200 dark:border-zinc-800 [a&]:hover:bg-zinc-100 dark:[a&]:hover:bg-zinc-800",
        success:
          "border-emerald-500/50 bg-emerald-500/10 text-emerald-600 dark:text-emerald-500 hover:bg-emerald-500/20",
        warning:
          "border-amber-500/50 bg-amber-500/10 text-amber-600 dark:text-amber-500 hover:bg-amber-500/20",
        error:
          "border-rose-500/50 bg-rose-500/10 text-rose-600 dark:text-rose-500 hover:bg-rose-500/20",
        info:
          "border-blue-500/50 bg-blue-500/10 text-blue-600 dark:text-blue-500 hover:bg-blue-500/20",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  },
);

function Badge({
  className,
  variant,
  asChild = false,
  ...props
}: React.ComponentProps<"span"> & VariantProps<typeof badgeVariants> & { asChild?: boolean }) {
  const Comp = asChild ? Slot : "span";

  return <Comp data-slot="badge" className={cn(badgeVariants({ variant }), className)} {...props} />;
}

export { Badge, badgeVariants };
