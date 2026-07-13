import re


def _plain_text(value: str) -> str:
    value = re.sub(r"!\[[^]]*]\([^)]*\)", "", value)
    value = re.sub(r"\[([^]]+)]\([^)]*\)", r"\1", value)
    value = re.sub(r"[`*_>#]", "", value)
    return " ".join(value.split())


def on_page_markdown(markdown, page, **kwargs):
    if not page.meta.get("description"):
        paragraphs = re.split(r"\n\s*\n", markdown)
        summary = next(
            (
                _plain_text(paragraph)
                for paragraph in paragraphs
                if paragraph.strip()
                and not paragraph.lstrip().startswith(
                    ("#", "!", "|", "- ", "* ", ">", "```")
                )
            ),
            "Guidance for using Mekuru on Android.",
        )
        page.meta["description"] = f"{page.title}: {summary}"[:158].rstrip()

    return markdown
