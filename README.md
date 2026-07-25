# CNN Accelerator on ZedBoard

A custom RTL-based CNN accelerator designed for the Xilinx ZedBoard (Zynq-7000 SoC). This repository accompanies the FPGA workshop covering RTL design, AXI IP packaging, Vivado integration, and Embedded Linux booting.

---

## Repository Structure

```
CNN-Accelerator-on-ZedBoard/
│
├── README.md
├── rtl/
├── axi_ip/
└── images/
```

---

## Hardware Requirements

- Xilinx ZedBoard
- MicroSD Card (8 GB or larger)
- USB-to-UART Cable
- USB-JTAG Cable

---

## Software Requirements

- Vivado 2025.2
- PetaLinux 2025.2
- Rufus
- PuTTY or Tera Term
- Git

---

## Workshop Flow

1. RTL Design
2. RTL Simulation
3. Package RTL as AXI IP
4. Vivado Block Design
5. Generate Bitstream
6. Export Hardware (XSA)
7. Build PetaLinux *(Reference Only)*
8. Prepare SD Card
9. Boot Embedded Linux

---

## Preparing the SD Card

### Step 1

Insert the microSD card into your Windows PC.

### Step 2

Open **Rufus**.

### Step 3

Configure Rufus as follows:

- Boot Selection: **Non-bootable**
- Partition Scheme: **MBR**
- File System: **FAT32**
- Cluster Size: **Default**

### Step 4

Click **START**.

### Step 5

Copy the following files to the SD card:

```
BOOT.BIN
image.ub
boot.scr
```

### Step 6

Safely eject the SD card.

---

## Booting Linux

1. Insert the SD card into the ZedBoard.
2. Set the Boot Mode switches to **SD Boot**.
3. Connect the USB-UART cable.
4. Open PuTTY or Tera Term.

Serial Settings:

```
Baud Rate : 115200
Data Bits : 8
Parity    : None
Stop Bits : 1
Flow Ctrl : None
```

Power on the board to observe the Linux boot process.

---

## Building PetaLinux (Reference Only)

The workshop provides pre-built boot files. Participants are **not required** to build PetaLinux during the session.

Typical commands:

```bash
petalinux-create project --template zynq --name cnn_accelerator

petalinux-config --get-hw-description=<XSA_PATH>

petalinux-build

petalinux-package boot \
    --fsbl images/linux/zynq_fsbl.elf \
    --fpga <BITSTREAM>.bit \
    --u-boot
```

---

## License

This repository is intended for educational and workshop purposes.
