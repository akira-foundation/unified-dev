import { Terminal } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { useI18n } from "@/i18n/i18n";

interface GhCliErrorDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  kind: "gh_not_installed" | "gh_not_authenticated" | null;
}

export function GhCliErrorDialog({ open, onOpenChange, kind }: GhCliErrorDialogProps) {
  const { t } = useI18n();

  if (!kind) return null;

  const isNotInstalled = kind === "gh_not_installed";

  const command = isNotInstalled ? "brew install gh" : "gh auth login";

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-[420px]">
        <DialogHeader>
          <DialogTitle>
            {t(isNotInstalled ? "ghCliError.notInstalled.title" : "ghCliError.notAuthenticated.title")}
          </DialogTitle>
          <DialogDescription>
            {t(isNotInstalled ? "ghCliError.notInstalled.description" : "ghCliError.notAuthenticated.description")}
          </DialogDescription>
        </DialogHeader>

         <div className="space-y-3 px-5 py-4">
          <p className="text-sm text-muted-foreground">
            {t(isNotInstalled ? "ghCliError.notInstalled.steps" : "ghCliError.notAuthenticated.steps")}
          </p>
          <div className="flex items-center gap-3 rounded-md bg-zinc-900 dark:bg-black/40 px-4 py-3">
            <Terminal className="h-4 w-4 shrink-0 text-muted-foreground" />
            <code className="text-sm font-mono text-foreground">{command}</code>
          </div>
          {isNotInstalled && (
            <p className="text-xs text-muted-foreground">
              {t("ghCliError.notInstalled.install")}:{" "}
              <span className="font-mono">https://cli.github.com</span>
            </p>
          )}
        </div>

         <DialogFooter>
           <Button variant="outline" size="sm" onClick={() => onOpenChange(false)}>
             {t("ghCliError.close")}
           </Button>
         </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
