import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import rehypeRaw from "rehype-raw";

export function MarkdownBody({ content }: { content: string }) {
  return (
    <div className="prose prose-sm dark:prose-invert max-w-none
      prose-p:my-1.5 prose-p:leading-relaxed
      prose-a:text-purple-600 dark:prose-a:text-purple-400 prose-a:no-underline hover:prose-a:underline
      prose-headings:font-semibold prose-headings:mt-3 prose-headings:mb-1
      prose-h1:text-base prose-h2:text-sm prose-h3:text-sm
      prose-ul:my-1.5 prose-ol:my-1.5 prose-li:my-0.5
      prose-pre:bg-zinc-100 dark:prose-pre:bg-zinc-800/80 prose-pre:rounded-lg prose-pre:text-xs prose-pre:overflow-x-auto
      prose-code:text-[12px] prose-code:bg-zinc-100 dark:prose-code:bg-zinc-800 prose-code:px-1 prose-code:py-0.5 prose-code:rounded prose-code:before:content-none prose-code:after:content-none
      prose-blockquote:border-l-zinc-300 dark:prose-blockquote:border-l-zinc-600 prose-blockquote:text-zinc-500 dark:prose-blockquote:text-zinc-400
      prose-hr:border-zinc-200 dark:prose-hr:border-zinc-700
      prose-img:rounded-lg prose-img:max-w-full
      prose-table:text-xs prose-th:bg-zinc-50 dark:prose-th:bg-zinc-800
    ">
      <ReactMarkdown remarkPlugins={[remarkGfm]} rehypePlugins={[rehypeRaw]}>
        {content}
      </ReactMarkdown>
    </div>
  );
}
