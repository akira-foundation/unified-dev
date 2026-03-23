import { useState } from "react";
import { Folder } from "lucide-react";
import { open as openDialog } from "@tauri-apps/plugin-dialog";
import {
  Dialog,
  DialogContent,
  DialogDescription,
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
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{t("dialogs.addRepository.title")}</DialogTitle>
          <DialogDescription>
            {t("dialogs.addRepository.description")}
          </DialogDescription>
        </DialogHeader>

        <Tabs
          defaultValue="local"
          className="w-full mt-4"
          onValueChange={(v) => setActiveTab(v as "local" | "clone")}
        >
          <TabsList variant="line" className="h-auto gap-8 mb-6">
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
                className="h-10"
              />
              <Button
                variant="outline"
                className="gap-2 h-10"
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
                className="h-10 pr-16"
              />
              {protocol && (
                <span className="absolute right-3 top-1/2 -translate-y-1/2 text-[10px] font-bold tracking-wider px-1.5 py-0.5 rounded bg-muted text-muted-foreground">
                  {protocol}
                </span>
              )}
            </div>
          </TabsContent>
        </Tabs>

        <DialogFooter className="mt-6">
          <Button
            variant="ghost"
            onClick={() => onOpenChange(false)}
          >
            {t("common.cancel")}
          </Button>
          <Button
            onClick={handleAdd}
            className="px-8"
            disabled={isAddDisabled}
          >
            {isLoading ? t("dialogs.addRepository.adding") : t("dialogs.addRepository.add")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
