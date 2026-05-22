import { useState, useCallback } from "react";
import { toast } from "sonner";

import type { ImagePart, ImageMediaType } from "@/types/agents";
import { IMAGE_SIZE_LIMIT } from "@/types/agents";

export function useImageAttachments() {
  const [attachedImages, setAttachedImages] = useState<ImagePart[]>([]);
  const [isDragOver, setIsDragOver] = useState(false);

  const readFileAsImagePart = useCallback((file: File): Promise<ImagePart | null> => {
    return new Promise((resolve) => {
      if (!file.type.startsWith("image/")) { resolve(null); return; }
      if (file.size > IMAGE_SIZE_LIMIT) {
        toast(`Image "${file.name}" exceeds the 5MB limit.`);
        resolve(null);
        return;
      }
      const reader = new FileReader();
      reader.onload = (e) => {
        const dataUrl = e.target?.result as string;
        const base64 = dataUrl.split(",")[1];
        resolve({ type: "image", data: base64, mediaType: file.type as ImageMediaType });
      };
      reader.onerror = () => resolve(null);
      reader.readAsDataURL(file);
    });
  }, []);

  const addImages = useCallback(async (files: FileList | File[]) => {
    const results = await Promise.all(Array.from(files).map(readFileAsImagePart));
    const valid = results.filter((p): p is ImagePart => p !== null);
    setAttachedImages((prev) => [...prev, ...valid]);
  }, [readFileAsImagePart]);

  const handlePaste = useCallback(async (e: React.ClipboardEvent<HTMLTextAreaElement>) => {
    const imageFiles = Array.from(e.clipboardData.items)
      .filter((item) => item.kind === "file" && item.type.startsWith("image/"))
      .map((item) => item.getAsFile())
      .filter((f): f is File => f !== null);
    if (imageFiles.length > 0) {
      e.preventDefault();
      await addImages(imageFiles);
    }
  }, [addImages]);

  const handleDrop = useCallback(async (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setIsDragOver(false);
    const files = Array.from(e.dataTransfer.files).filter((f) => f.type.startsWith("image/"));
    if (files.length > 0) await addImages(files);
  }, [addImages]);

  const removeImage = useCallback((index: number) => {
    setAttachedImages((prev) => prev.filter((_, i) => i !== index));
  }, []);

  const clearImages = useCallback(() => setAttachedImages([]), []);

  return {
    attachedImages,
    addImages,
    handlePaste,
    handleDrop,
    removeImage,
    clearImages,
    isDragOver,
    setIsDragOver,
  };
}
