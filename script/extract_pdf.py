from pypdf import PdfReader

reader = PdfReader("Good.Software.Release.Notes.pdf")
text = ""
for page in reader.pages:
    text += page.extract_text() + "\n"

with open("Good.Software.Release.Notes.txt", "w", encoding="utf-8") as f:
    f.write(text)
