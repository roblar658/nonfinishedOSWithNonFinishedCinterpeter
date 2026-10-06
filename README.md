# CustomC-OS v2.0: x86 Operativsystem med MSB Bootloader & Terminal

Et selvstendig x86 operativsystem med **MSB (Master Boot Sector / MBR)**, **operativsystem-kjerne**, **interaktiv terminal**, **innebygd tekst-editor** og **C-kompilator**.

---

## 🚀 Hovedfunksjoner

1. **MSB (Master Boot Sector / MBR Bootloader)**:
   - Skrevet i 16-bit x86 assembly (`boot/msb_boot.asm`).
   - Ligger i sektor 0 på disken (nøyaktig 512 bytes, avsluttes med signaturen `0xAA55`).
   - Lastes av BIOS på `0000:7C00h`.
   - Setter opp stack og segmenter, tilbakestiller diskkontrolleren, leser kjernesektorene inn i fysisk minne på `0x1000:0000`, og hopper direkte til kjernen.

2. **Operativsystem-Kjerne & Terminal**:
   - Skrevet i x86 assembly (`kernel/kernel.asm`) og plassert på `0x1000:0000`.
   - **Dual I/O Driver**: Støtter både VGA 80x25 fargetekstmodus og 115200 baud 8N1 COM1 UART seriell port for terminalstyring.
   - **Interaktivt kommandoskall**: Prompt med linjeredigering, tegnbuffer og sanntids respons.

3. **Innebygde Terminalkommandoer**:
   - `help` / `?`: Viser komplett hjelpemeny med alle tilgjengelige kommandoer.
   - `dir` / `ls`: Lister filer i operativsystemets filsystem (`/workspace`).
   - `cat <fil>` / `type <fil>`: Skriver ut kildekoden til en fil i terminalen.
   - `edit <fil>`: Interaktiv editor direkte i terminalen. Skriv kode, bruk `:w` for å lagre og `:q` for å avslutte.
   - `cc <fil>` / `compile <fil>`: Kompilerer en C-fil med OS-ets innebygde parser og kodegenerator.
   - `run <fil>`: Kompilerer og kjører C-programmet i operativsystemet og viser utskrift (stdout).
   - `asm <fil>`: Viser den genererte x86 assembly-koden for filen.
   - `info` / `sysinfo`: Viser OS-versjon, MSB-adresse, kjernesegment og arkitektur.
   - `time`: Viser reelt klokkeslett direkte fra datamaskinens CMOS Real-Time Clock (RTC).
   - `date`: Viser gjeldende dato fra CMOS RTC.
   - `calc <a> <op> <b>`: Innebygd terminalkalkulator for beregninger (`+`, `-`, `*`, `/`).
   - `color <0-15>`: Endrer forgrunnsfarge i terminalen.
   - `echo <tekst>`: Skriver ut tekst.
   - `cls` / `clear`: Nullstiller terminalskjermen.
   - `mem`: Viser minnekartet til systemet (IVT, BDA, MSB, Kjerne, Stakk, VGA).
   - `reboot`: Restarter datamaskinen via tastaturkontroller-puls (Port 0x64).
   - `shutdown` / `exit`: Avslutter maskinen og lukker terminalen.

4. **Forhåndsinstallerte C-demoer**:
   - `hello.c` – Hallo Verden med printf.
   - `factorial.c` – Rekursiv fakultetsberegning.
   - `fibonacci.c` – Fibonacci tallrekke.
   - `sorting.c` – Boblesortering.
   - `struct_demo.c` – C-strukturer og pekere.

---

## 📁 Prosjektstruktur

```
C:\dev\custom_c_os\
├── boot/
│   ├── msb_boot.asm       # Master Boot Sector (MSB/MBR, 512 bytes)
│   └── msb_boot.bin       # Ferdigkompilert MBR bootsector
├── kernel/
│   ├── kernel.asm         # Operativsystem-kjerne, terminal og skall
│   └── kernel.bin         # Ferdigkompilert OS-kjerne (32 KB space)
├── workspace/             # Eksterne kildekodefiler
├── custom_c_os.img        # Bootbart 1.44MB disk-image (MSB + Kjerne)
├── build.ps1              # Byggeskript for MSB, kjerne og disk-image
├── run.ps1                # Starter operativsystemet i terminalen
├── setup.ps1              # Alt-i-ett installasjon og oppstart
├── Dockerfile             # Terminal-container
├── docker-compose.yml     # Compose for terminal
└── README.md
```

---

## ⚡ Kom i gang

### 1. Bygg og start
Åpne PowerShell i mappen:
```powershell
cd C:\dev\custom_c_os
.\setup.ps1
```

### 2. Kjøre terminalen
- **I terminalvindu (QEMU)**:
  ```powershell
  .\run.ps1
  ```
- **I gjeldende konsoll**:
  ```powershell
  .\run.ps1 -Console
  ```

---

## 💻 Eksempler i Terminalen

```text
[MSB] CustomC-OS Master Boot Sector v2.0
[MSB] Laster kjerne fra disk...
[MSB] Boot OK! Starter terminal...
==================================================================
   CustomC-OS v2.0 | x86 Operativsystem                           
   Terminal - C-Kompilator & Editor                               
==================================================================
Velkommen til CustomC-OS terminalen!
Skriv 'help' for en oversikt over alle kommandoer.

CustomC-OS:\> dir
Volum i stasjon C er CustomC-OS
Filinnhold i /workspace (Virtuelt Filsystem):
----------------------------------------------------
hello.c         <C-KILDE>     [Kompilerbar C-kode]
factorial.c     <C-KILDE>     [Kompilerbar C-kode]
fibonacci.c     <C-KILDE>     [Kompilerbar C-kode]
sorting.c       <C-KILDE>     [Kompilerbar C-kode]
struct_demo.c   <C-KILDE>     [Kompilerbar C-kode]

CustomC-OS:\> run hello.c
[*] [CustomC-OS] Kompilerer og kjorer: hello.c
  [1/3] Leksikalsk analyse (Lexer): Genererte symboltokens... OK
  [2/3] Syntaks-analyse (AST Parser) & Typesjekk... OK
  [3/3] Genererer x86 maskinkode & symbolkobling... OK

--- Programutskrift (Standard Output) ---
Hallo fra CustomC-OS!
Kjores direkte i CustomC-OS terminalen.
-----------------------------------------
[*] Program fullfort med returkode 0.

CustomC-OS:\> edit min_fil.c
=== CustomC-OS Terminal Editor: min_fil.c ===
Skriv inn eller lim inn kode/tekst direkte i redigeringsmodus.
Kommandomodus slaas paa med [ESC] (slaas av etter utfoert kommando):
  [ESC] -> w   = Lagre til filsystemet
  [ESC] -> wq  = Lagre og avslutt editor
  [ESC] -> q   = Avslutt editor uten aa lagre
----------------------------------------------------
[Redigeringsmodus aktiv - lim inn eller skriv under (ESC for kommando)]:
  1 | int main() {
  2 |     return 123;
  3 | }
[Kommando] : wq
[+] Filen ble lagret i filsystemet!
[*] Avsluttet editor.

CustomC-OS:\> run min_fil.c
[*] [CustomC-OS] Kompilerer og kjorer: min_fil.c
...
```
