from reportlab.lib.pagesizes import A4, landscape
from reportlab.pdfgen import canvas

OUT = "/mnt/user-data/outputs/Soll-Liste_Test_Universitaetsspital_Basel_OP.pdf"

# Jedes Foto = 1 Position (1 Stk.). iVascular: 3 Strichcodes pro Teil, zählt als 1.
rows = [
    ("GET-HEW2810BRIDGE", "31.01.2031", "1668718041/26B05", "Hemabridge D 28x10 mm L 35x40 cm"),
    ("GET-HEW2810BRIDGE", "30.11.2030", "1661543174/25M25", "Hemabridge D 28x10 mm L 35x40 cm"),
    ("GET-HEW3010BRIDGE", "31.12.2030", "1663045780/26A08", "Hemabridge D 30x10 mm L 35x40 cm"),
    ("GET-IGK0008-40", "31.01.2031", "1670721860/26B19", "Straight D 8 mm L 40 cm"),
    ("GET-IGK0010-20", "30.11.2030", "1661523386/25M25", "Straight D 10 mm L 20 cm"),
    ("GET-IGK0010-20", "30.11.2030", "1661525920/25M25", "Straight D 10 mm L 20 cm"),
    ("IVAS-SPCBCC35140090027", "24.06.2029", "2611811", "iCOVER OTW 9 x 27 mm"),
    ("IVAS-SPCBCC35140080057", "30.09.2029", "2617269", "iCOVER OTW 8 x 57 mm"),
    ("IVAS-SPCBCC35140080057", "30.09.2029", "2617269", "iCOVER OTW 8 x 57 mm"),
    ("IVAS-SPCBCC35140080057", "30.09.2029", "2617269", "iCOVER OTW 8 x 57 mm"),
    ("IVAS-SPCBCC35140080057", "30.09.2029", "2617269", "iCOVER OTW 8 x 57 mm"),
    ("IVAS-SPCBCC35140080037", "04.05.2029", "2606969", "iCOVER OTW 8 x 37 mm"),
    ("IVAS-SPCBCC35140080027", "19.07.2029", "2612784", "iCOVER OTW 8 x 27 mm"),
    ("IVAS-SPCBCC35140070057", "05.03.2028", "2502617", "iCOVER OTW 7 x 57 mm"),
    ("IVAS-SPCBCC35140070037", "23.08.2029", "2613985", "iCOVER OTW 7 x 37 mm"),
    ("IVAS-SPCBCC35140100057", "11.03.2029", "2601491", "iCOVER OTW 10 x 57 mm"),
    ("IVAS-SPCBCC35140080037", "29.07.2029", "2614016", "iCOVER OTW 8 x 37 mm"),
    ("IVAS-SPCBCC35140080027", "05.08.2029", "2614046", "iCOVER OTW 8 x 27 mm"),
    ("IVAS-SPCBCC35080070037", "06.05.2029", "2608435", "iCOVER OTW 7 x 37 mm"),
    ("IVAS-SPCBCC35140080027", "05.08.2029", "2614046", "iCOVER OTW 8 x 27 mm"),
    ("IVAS-SPCBCC35140050027", "01.06.2029", "2610552", "iCOVER OTW 5 x 27 mm"),
    ("IVAS-SPCBCC35140070057", "30.08.2029", "2613990", "iCOVER OTW 7 x 57 mm"),
    ("IVAS-SPCBCC35140080037", "29.07.2029", "2614016", "iCOVER OTW 8 x 37 mm"),
    ("GET-IGK0008-20", "31.08.2031", "1707682968/26J17", "Straight D 8 mm L 20 cm"),
    ("GET-IGK0006-20SG", "31.08.2028", "1639487822/25J26", "Straight D 6 mm L 20 cm"),
    ("GET-IGK1809S", "31.12.2028", "1661994310/26A08", "Bifurcated D 18x9 mm L 50 cm"),
    ("GET-IGW0020-15", "31.12.2027", "1440358475/23A20", "Straight D 20 mm L 15 cm"),
    ("GET-HEW2810BRIDGE", "30.06.2031", "1700564071/26G16", "Hemabridge D 28x10 mm L 35x40 cm"),
    ("GET-HEWAA2610080810/1", "31.03.2031", "1685043048/26D30", "Aortic Arch D 26x10x8x8x10 mm L 50x30x30x30x30 cm"),
    ("IVAS-SPCBCC35080100037", "08.12.2028", "2517910", "iCOVER OTW 10 x 37 mm"),
    ("IVAS-SPCBCC35140080057", "26.07.2029", "2614000", "iCOVER OTW 8 x 57 mm"),
]
assert len(rows) == 31

W, H = landscape(A4)
c = canvas.Canvas(OUT, pagesize=landscape(A4))
c.setTitle("Soll-Liste Test Universitätsspital Basel OP")
c.setAuthor("MCM Schaublin AG")

y = H - 40
c.setFont("Helvetica-Bold", 13)
c.drawString(40, y, "Soll-Liste Konsignation – Testdatei")
y -= 20
c.setFont("Helvetica", 10)
c.drawString(40, y, "Standort: Universitätsspital Basel OP")
y -= 26

c.setFont("Courier", 9)
for art, mhd, sc, bez in rows:
    c.drawString(40, y, f"{art} {mhd} {sc} {bez} 1 Stk.")
    y -= 14

c.setFont("Helvetica-Oblique", 8)
c.drawString(40, 30, "Erstellt aus Fotos der Etiketten am 15.11.2026. SN/Charge vor Verwendung am Produkt prüfen.")
c.showPage()
c.save()
print("ok", len(rows))
