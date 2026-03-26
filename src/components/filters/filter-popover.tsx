import type { ComponentPropsWithoutRef, ComponentRef } from "react";
import { forwardRef } from "react";

import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { cn } from "@/lib/utils";

const FilterPopover = Popover;
const FilterPopoverTrigger = PopoverTrigger;

const FilterPopoverContent = forwardRef<
  ComponentRef<typeof PopoverContent>,
  ComponentPropsWithoutRef<typeof PopoverContent>
>(({ className, align = "end", ...props }, ref) => (
  <PopoverContent
    ref={ref}
    align={align}
    className={cn("w-64 p-0 bg-card text-card-foreground", className)}
    {...props}
  />
));

FilterPopoverContent.displayName = "FilterPopoverContent";

export { FilterPopover, FilterPopoverContent, FilterPopoverTrigger };
