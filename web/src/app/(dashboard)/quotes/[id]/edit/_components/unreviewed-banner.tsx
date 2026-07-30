import { unreviewedBannerCopy } from "../../_lib/review-state";

interface UnreviewedBannerProps {
  count: number;
  id?: string;
}

/** The editor's unreviewed-AI-lines banner. Accepts an optional `id` so a
 *  caller that needs an `aria-describedby` anchor can own it without this
 *  component inventing one. */
export function UnreviewedBanner({ count, id }: UnreviewedBannerProps) {
  const { heading, body } = unreviewedBannerCopy(count);

  return (
    <div id={id} data-testid="unreviewed-banner" className="rounded-lg bg-secondary p-4">
      <p className="text-sm font-medium">{heading}</p>
      <p className="text-sm">{body}</p>
    </div>
  );
}
