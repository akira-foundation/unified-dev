import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";
import type { LucideIcon } from "lucide-react";

interface IconButtonProps extends React.ComponentProps<typeof Button> {
  icon: LucideIcon;
  tooltip?: string;
  className?: string;
  onClick?: () => void;
}

export function IconButton({ icon: Icon, tooltip, className, onClick, ...props }: IconButtonProps) {
  const button = (
    <Button
      variant="outline"
      size="icon"
      onClick={onClick}
      className={cn(
        "h-10 w-10 rounded-full border-zinc-200 bg-white text-zinc-500 hover:bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-900 dark:text-zinc-400 dark:hover:bg-zinc-800",
        className,
      )}
      {...props}
    >
      <Icon className="h-5 w-5" />
    </Button>
  );

  if (!tooltip) {
    return button;
  }

  return (
    <TooltipProvider>
      <Tooltip delayDuration={300}>
        <TooltipTrigger asChild>{button}</TooltipTrigger>
        <TooltipContent>
          <p>{tooltip}</p>
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );
}
