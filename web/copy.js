// Adds a Copy button to every code block; without JS the block just reads.
const labels =
  document.documentElement.lang === "ar"
    ? { copy: "نسخ", done: "تم النسخ", failed: "تعذر النسخ" }
    : { copy: "Copy", done: "Copied", failed: "Copy failed" };

for (const block of document.querySelectorAll(".code")) {
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = labels.copy;
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(
        block.querySelector("pre").textContent.trim(),
      );
      button.textContent = labels.done;
    } catch {
      button.textContent = labels.failed;
    }
    setTimeout(() => {
      button.textContent = labels.copy;
    }, 1800);
  });
  block.append(button);
}
