import { useState } from "react";
import { Plus, Trash2, Loader2, Link2, Unplug, RefreshCcw } from "lucide-react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { PageLayout } from "@/components/layout/page-layout";
import { PageHeader, PageHeaderMeta, PageHeaderTitle, PageHeaderActions } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Card, CardContent } from "@/components/ui/card";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";
import { invoke } from "@tauri-apps/api/core";
import { queryKeys } from "@/lib/query-keys";
import { toast } from "sonner";

interface PresetMcpServer {
  id: string;
  name: string;
  url: string;
  description: string;
  iconClass: string;
  textIcon: string;
}

const PRESET_MCP_SERVERS: PresetMcpServer[] = [
  {
    id: "mcp-linear-app",
    name: "Linear",
    url: "https://mcp.linear.app",
    description: "Project management — issues, cycles, projects",
    iconClass: "bg-violet-500/10 text-violet-400",
    textIcon: "LN",
  },
];

interface McpServer {
  id: string;
  name: string;
  url: string;
  access_token: string | null;
  token_type: string;
  enabled: boolean;
  created_at: string;
}

export function McpPage() {
  const queryClient = useQueryClient();
  const [addOpen, setAddOpen] = useState(false);
  const [addName, setAddName] = useState("");
  const [addUrl, setAddUrl] = useState("");
  const [connectingId, setConnectingId] = useState<string | null>(null);
  const [quickConnectingId, setQuickConnectingId] = useState<string | null>(null);

  const { data: servers = [], isLoading, refetch } = useQuery({
    queryKey: queryKeys.mcpServers(),
    queryFn: () => invoke<McpServer[]>("list_mcp_servers"),
  });

  const installedIds = new Set(servers.map((s) => s.id));
  const availablePresets = PRESET_MCP_SERVERS.filter((p) => !installedIds.has(p.id));

  const addServer = useMutation({
    mutationFn: ({ name, url }: { name: string; url: string }) =>
      invoke<McpServer>("add_mcp_server", { name, url }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.mcpServers() });
      setAddOpen(false);
      setAddName("");
      setAddUrl("");
    },
    onError: (e: unknown) => toast.error(String(e)),
  });

  const removeServer = useMutation({
    mutationFn: (id: string) => invoke("remove_mcp_server", { id }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: queryKeys.mcpServers() }),
    onError: (e: unknown) => toast.error(String(e)),
  });

  const toggleEnabled = useMutation({
    mutationFn: ({ id, enabled }: { id: string; enabled: boolean }) =>
      invoke("set_mcp_server_enabled", { id, enabled }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: queryKeys.mcpServers() }),
    onError: (e: unknown) => toast.error(String(e)),
  });

  const connect = useMutation({
    mutationFn: async (id: string) => {
      setConnectingId(id);
      await invoke("connect_mcp_server", { id });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.mcpServers() });
      toast.success("Connected successfully");
    },
    onError: (e: unknown) => toast.error(String(e)),
    onSettled: () => setConnectingId(null),
  });

  const disconnect = useMutation({
    mutationFn: (id: string) => invoke("disconnect_mcp_server", { id }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: queryKeys.mcpServers() }),
    onError: (e: unknown) => toast.error(String(e)),
  });

  const quickConnect = useMutation({
    mutationFn: async ({ name, url, presetId }: { name: string; url: string; presetId: string }) => {
      setQuickConnectingId(presetId);
      const server = await invoke<McpServer>("add_mcp_server", { name, url });
      await invoke("connect_mcp_server", { id: server.id });
      return server;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.mcpServers() });
      toast.success("Connected successfully");
    },
    onError: (e: unknown) => toast.error(String(e)),
    onSettled: () => setQuickConnectingId(null),
  });

  const handleAdd = () => {
    if (!addName.trim() || !addUrl.trim()) return;
    addServer.mutate({ name: addName.trim(), url: addUrl.trim() });
  };

  return (
    <PageLayout scroll>
      <div className="mx-auto w-full max-w-6xl pb-12">
        <PageHeader className="px-8">
          <div>
            <div className="flex items-center gap-3">
              <PageHeaderTitle className="text-3xl">MCP Servers</PageHeaderTitle>
              <span className="flex items-center gap-1.5 px-2.5 py-1 rounded-md dark:bg-white/5 bg-black/5 dark:border-white/5 border-border border text-[9px] text-zinc-500 shrink-0 font-black uppercase tracking-wider h-fit">
                Beta
              </span>
            </div>
            <PageHeaderMeta>
              <span>Connect Model Context Protocol servers to extend AI capabilities</span>
            </PageHeaderMeta>
          </div>
          <PageHeaderActions className="gap-3">
            <Button
              variant="ghost"
              className="text-zinc-400 hover:text-foreground dark:hover:bg-white/5 hover:bg-black/5 font-medium text-xs"
              onClick={() => refetch()}
            >
              <RefreshCcw className="mr-2 h-3.5 w-3.5" />
              Refresh
            </Button>
            <Button className="gap-1.5" onClick={() => setAddOpen(true)}>
              <Plus className="h-4 w-4" strokeWidth={3} />
              Add Server
            </Button>
          </PageHeaderActions>
        </PageHeader>

        <div className="px-8 mt-4">
          <h2 className="text-[13px] font-black uppercase tracking-[0.15em] text-zinc-500 mb-6">
            Connected Servers
          </h2>

          {isLoading ? (
            <div className="flex flex-col gap-3">
              {Array.from({ length: 3 }).map((_, i) => (
                <div key={i} className="h-[66px] rounded-xl dark:bg-white/[0.03] bg-black/[0.03] animate-pulse" />
              ))}
            </div>
          ) : servers.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-16 text-center">
              <div className="h-12 w-12 rounded-xl dark:bg-white/5 bg-black/5 flex items-center justify-center mb-4">
                <Link2 className="h-6 w-6 text-zinc-500" />
              </div>
              <p className="text-sm font-semibold text-zinc-400 mb-1">No MCP servers</p>
              <p className="text-xs text-zinc-600 max-w-xs">
                Add a server URL to connect an MCP-compatible service and expose its tools to the AI.
              </p>
            </div>
          ) : (
            <div className="flex flex-col gap-3">
              {servers.map((server) => {
                const isConnecting = connectingId === server.id;
                const isAuthenticated = !!server.access_token;
                return (
                  <Card
                    key={server.id}
                    className="group overflow-hidden dark:hover:border-white/10 hover:border-border transition-colors"
                  >
                    <CardContent className="p-4 flex items-center justify-between gap-4">
                      <div className="flex items-center gap-4 min-w-0 flex-1">
                        <div className="h-10 w-10 shrink-0 rounded-md dark:bg-white/5 bg-black/5 border dark:border-white/5 border-border flex items-center justify-center">
                          <Link2 className="h-4 w-4 text-zinc-500" />
                        </div>
                        <div className="flex flex-col gap-0.5 min-w-0">
                          <div className="flex items-center gap-2">
                            <span className="text-[14px] font-bold dark:text-zinc-100 text-foreground truncate">
                              {server.name}
                            </span>
                            <span className={cn(
                              "shrink-0 px-1.5 py-0.5 rounded text-[9px] font-black uppercase tracking-wider border",
                              isAuthenticated
                                ? "bg-green-500/10 text-green-400 border-green-500/20"
                                : "bg-zinc-500/10 text-zinc-400 border-zinc-500/20"
                            )}>
                              {isAuthenticated ? "Connected" : "Not connected"}
                            </span>
                          </div>
                          <span className="text-[12px] text-zinc-500 truncate font-mono">
                            {server.url}
                          </span>
                        </div>
                      </div>

                      <div
                        className="flex items-center gap-2 shrink-0"
                        onClick={(e) => e.stopPropagation()}
                      >
                        {isAuthenticated ? (
                          <button
                            className="opacity-0 group-hover:opacity-100 flex items-center gap-1.5 px-2 h-8 rounded-md text-zinc-400 hover:text-red-400 hover:bg-red-500/10 transition-all text-xs font-semibold"
                            onClick={() => disconnect.mutate(server.id)}
                          >
                            <Unplug className="h-3.5 w-3.5" />
                            Disconnect
                          </button>
                        ) : (
                          <button
                            disabled={isConnecting}
                            className="opacity-0 group-hover:opacity-100 flex items-center gap-1.5 px-2 h-8 rounded-md text-zinc-400 hover:text-foreground dark:hover:bg-white/10 hover:bg-black/10 disabled:opacity-50 disabled:cursor-not-allowed transition-all text-xs font-semibold"
                            onClick={() => connect.mutate(server.id)}
                          >
                            {isConnecting ? (
                              <Loader2 className="h-3.5 w-3.5 animate-spin" />
                            ) : (
                              <Link2 className="h-3.5 w-3.5" />
                            )}
                            {isConnecting ? "Connecting..." : "Connect"}
                          </button>
                        )}

                        <button
                          className="opacity-0 group-hover:opacity-100 flex items-center gap-1.5 px-2 h-8 rounded-md text-red-400 hover:text-red-300 hover:bg-red-500/10 transition-all text-xs font-semibold"
                          onClick={() => removeServer.mutate(server.id)}
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                          Remove
                        </button>

                        <Switch
                          checked={server.enabled}
                          onCheckedChange={(checked) => toggleEnabled.mutate({ id: server.id, enabled: checked })}
                          className="data-[state=checked]:bg-purple-500 ml-1"
                        />
                      </div>
                    </CardContent>
                  </Card>
                );
              })}
            </div>
          )}
        </div>

        {availablePresets.length > 0 && (
          <div className="px-8 mt-10">
            <h2 className="text-[13px] font-black uppercase tracking-[0.15em] text-zinc-500 mb-6">
              Available Integrations
            </h2>
            <div className="flex flex-col gap-3">
              {availablePresets.map((preset) => {
                const isConnecting = quickConnectingId === preset.id;
                return (
                  <Card
                    key={preset.id}
                    className="group overflow-hidden dark:hover:border-white/10 hover:border-border transition-colors"
                  >
                    <CardContent className="p-4 flex items-center justify-between gap-4">
                      <div className="flex items-center gap-4 min-w-0 flex-1">
                        <div className={cn(
                          "h-10 w-10 shrink-0 rounded-md border dark:border-white/5 border-border flex items-center justify-center font-black text-xs",
                          preset.iconClass,
                        )}>
                          {preset.textIcon}
                        </div>
                        <div className="flex flex-col gap-0.5 min-w-0">
                          <span className="text-[14px] font-bold dark:text-zinc-100 text-foreground truncate">
                            {preset.name}
                          </span>
                          <span className="text-[12px] text-zinc-500 truncate">
                            {preset.description}
                          </span>
                        </div>
                      </div>
                      <button
                        disabled={isConnecting}
                        className="flex items-center gap-1.5 px-3 h-8 rounded-md text-zinc-400 hover:text-foreground dark:hover:bg-white/10 hover:bg-black/10 disabled:opacity-50 disabled:cursor-not-allowed transition-all text-xs font-semibold"
                        onClick={() => quickConnect.mutate({ name: preset.name, url: preset.url, presetId: preset.id })}
                      >
                        {isConnecting ? (
                          <Loader2 className="h-3.5 w-3.5 animate-spin" />
                        ) : (
                          <Link2 className="h-3.5 w-3.5" />
                        )}
                        {isConnecting ? "Connecting..." : "Connect"}
                      </button>
                    </CardContent>
                  </Card>
                );
              })}
            </div>
          </div>
        )}
      </div>

      <Dialog open={addOpen} onOpenChange={setAddOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Add MCP Server</DialogTitle>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-2">
            <div className="flex flex-col gap-2">
              <Label htmlFor="mcp-name">Name</Label>
              <Input
                id="mcp-name"
                placeholder="Linear"
                value={addName}
                onChange={(e) => setAddName(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && handleAdd()}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="mcp-url">Server URL</Label>
              <Input
                id="mcp-url"
                placeholder="https://mcp.linear.app"
                value={addUrl}
                onChange={(e) => setAddUrl(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && handleAdd()}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setAddOpen(false)}>Cancel</Button>
            <Button
              onClick={handleAdd}
              disabled={!addName.trim() || !addUrl.trim() || addServer.isPending}
            >
              {addServer.isPending ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
              Add Server
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </PageLayout>
  );
}
