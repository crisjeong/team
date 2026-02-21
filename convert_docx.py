import pypandoc
import os

def ensure_pandoc():
    try:
        pypandoc.get_pandoc_version()
        print("Pandoc is already installed.")
    except OSError:
        print("Downloading pandoc...")
        pypandoc.download_pandoc()
        print("Pandoc downloaded successfully.")

def convert_to_docx():
    # Convert HTML to docx for better styling retention
    input_file = "release_notes_styled.html"
    output_file = "Good.Software.Release.Notes_ko.docx"
    
    # We can use pypandoc to convert
    print(f"Converting {input_file} to {output_file}...")
    pypandoc.convert_file(
        input_file,
        'docx',
        outputfile=output_file
    )
    print("Conversion complete!")

if __name__ == "__main__":
    ensure_pandoc()
    convert_to_docx()
