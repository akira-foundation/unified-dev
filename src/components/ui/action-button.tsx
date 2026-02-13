import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

interface ActionButtonProps extends React.ComponentProps<typeof Button> {
  className?: string;
  children: React.ReactNode;
}

export function ActionButton({ className, children, ...props }: ActionButtonProps) {
  return (
    <Button
      className={cn("h-10 rounded-full bg-foreground text-background hover:bg-foreground/90 font-medium", className)}
      {...props}
    >
      {children}
    </Button>
  );
}
