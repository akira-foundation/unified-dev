import { useState } from "react";
import { Folder } from "lucide-react";
import { open as openDialog } from "@tauri-apps/plugin-dialog";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useI18n } from "@/i18n/i18n";

interface AddRepositoryDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onAdd: (value: string, mode: "local" | "clone") => void;
  isLoading?: boolean;
}

function detectProtocol(url: string): "SSH" | "HTTPS" | null {
  if (url.startsWith("git@")) return "SSH";
  if (url.startsWith("https://") || url.startsWith("http://")) return "HTTPS";
  return null;
}

export function AddRepositoryDialog({
  open,
  onOpenChange,
  onAdd,
  isLoading,
}: AddRepositoryDialogProps) {
  const { t } = useI18n();
  const [localPath, setLocalPath] = useState("");
  const [cloneUrl, setCloneUrl] = useState("");
  const [activeTab, setActiveTab] = useState<"local" | "clone">("local");

  const protocol = detectProtocol(cloneUrl);

  const handleAdd = () => {
    if (activeTab === "local" && localPath) {
      onAdd(localPath, "local");
      setLocalPath("");
    } else if (activeTab === "clone" && cloneUrl) {
      onAdd(cloneUrl, "clone");
      setCloneUrl("");
    }
  };

  const isAddDisabled = isLoading || (activeTab === "local" ? !localPath : !cloneUrl);

  const handleBrowse = async () => {
    try {
      const selected = await openDialog({
        directory: true,
        multiple: false,
      });
      if (selected && typeof selected === "string") {
        setLocalPath(selected);
      }
    } catch (error) {
      console.error("Failed to select directory:", error);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-[420px] gap-0 overflow-hidden p-0">
        <DialogHeader className="border-b border-border px-5 pt-5 pb-4">
          <DialogTitle className="text-base">{t("dialogs.addRepository.title")}</DialogTitle>
          <p className="mt-1.5 text-sm text-muted-foreground">
            {t("dialogs.addRepository.description")}
          </p>
        </DialogHeader>

        <Tabs
          defaultValue="local"
          className="w-full px-5 py-4"
          onValueChange={(v) => setActiveTab(v as "local" | "clone")}
        >
          <TabsList variant="line" className="mb-6 h-auto gap-8">
            <TabsTrigger
              value="local"
              className="px-0 py-2 lowercase first-letter:uppercase"
            >
              {t("dialogs.addRepository.localPath")}
            </TabsTrigger>
            <TabsTrigger
              value="clone"
              className="px-0 py-2 lowercase first-letter:uppercase"
            >
              {t("dialogs.addRepository.cloneUrl")}
            </TabsTrigger>
          </TabsList>

          <TabsContent value="local" className="space-y-4 mt-0">
            <div className="flex gap-2">
              <Input
                placeholder={t("dialogs.addRepository.pathPlaceholder")}
                value={localPath}
                onChange={(e) => setLocalPath(e.target.value)}
              />
              <Button
                variant="outline"
                className="h-8 gap-2 border-zinc-200 bg-zinc-100 text-zinc-700 hover:bg-zinc-200 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-200 dark:hover:bg-zinc-700"
                onClick={handleBrowse}
              >
                <Folder className="h-4 w-4" />
                {t("dialogs.addRepository.browse")}
              </Button>
            </div>
          </TabsContent>

          <TabsContent value="clone" className="space-y-4 mt-0">
            <div className="relative">
              <Input
                placeholder="https://github.com/owner/repo.git"
                value={cloneUrl}
                onChange={(e) => setCloneUrl(e.target.value)}
                className="pr-16"
              />
              {protocol && (
                <span className="absolute right-3 top-1/2 -translate-y-1/2 rounded border border-zinc-200 bg-zinc-50 px-1.5 py-0.5 text-[10px] font-bold tracking-wider text-zinc-500 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-400">
                  {protocol}
                </span>
              )}
            </div>
          </TabsContent>
        </Tabs>

        <DialogFooter className="flex gap-2 px-5 pb-5 pt-0">
          <Button
            variant="outline"
            size="sm"
            onClick={() => onOpenChange(false)}
          >
            {t("common.cancel")}
          </Button>
          <Button
            onClick={handleAdd}
            size="sm"
            className="flex-1 bg-purple-600 text-white hover:bg-purple-700"
            disabled={isAddDisabled}
          >
            {isLoading ? t("dialogs.addRepository.adding") : t("dialogs.addRepository.add")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
