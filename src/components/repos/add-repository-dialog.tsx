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
  onAdd: (path: string) => void;
  isLoading?: boolean;
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

  const handleAdd = () => {
    if (localPath) {
      onAdd(localPath);
      onOpenChange(false);
      setLocalPath("");
    }
  };

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

        <Tabs defaultValue="local" className="w-full mt-4">
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
            <Input
              placeholder="https://github.com/owner/repo.git"
              value={cloneUrl}
              onChange={(e) => setCloneUrl(e.target.value)}
              className="h-10"
            />
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
            disabled={isLoading || !localPath}
          >
            {isLoading ? t("dialogs.addRepository.adding") : t("dialogs.addRepository.add")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
