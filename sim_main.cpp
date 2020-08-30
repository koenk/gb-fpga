#include <chrono>
#include <cstdio>

#include "Vmain.h"
#include "verilated.h"

extern "C" {
#include "gui.h"
}

#define RES_X 160
#define RES_Y 144
#define ZOOM  4

using namespace std::chrono;

class MemRegion
{
protected:
    uint8_t *mem;
    uint16_t base, end;
public:
    MemRegion(uint16_t base, uint16_t end)
        : base(base), end(end)
    {
        mem = (uint8_t *)calloc(end - base, 1);
    }

    void update(uint16_t addr, bool do_write, uint8_t val, uint8_t *rv)
    {
        if (addr >= base && addr < end) {
            if (do_write)
                mem[addr - base] = val;
            else
                *rv = mem[addr - base];
        }
    }
};

#define ROMHDR_CART_TYPE 0x0147
#define ROMHDR_RAM_SIZE 0x0149

#define CART_TYPE_ROMONLY 0x00
#define CART_TYPE_MBC3_RAM_BAT 0x13

#define ROMBANK_SIZE 0x4000
#define RAMBANK_SIZE 0x2000

class Cartridge
{
protected:
    size_t rom_size;
    uint8_t *rom;
    Cartridge(size_t rom_size, uint8_t *rom_data)
            : rom_size(rom_size), rom(rom_data)
    {
    }
public:
    virtual uint8_t read(uint16_t addr) = 0;
    virtual void write(uint16_t addr, uint8_t data) = 0;

    void update(uint16_t addr, bool do_write, uint8_t val, uint8_t *rv)
    {
        if (addr < 0x8000 || (addr >= 0xA000 && addr < 0xC000)) {
            if (do_write)
                write(addr, val);
            else
                *rv = read(addr);
        }
    }
};

class CartRomOnly : public Cartridge
{
public:
    CartRomOnly(size_t rom_size, uint8_t *rom_data)
        : Cartridge(rom_size, rom_data)
    {
    }

    virtual uint8_t read(uint16_t addr)
    {
        if (addr >= 0x8000 || addr > rom_size)
            return 0xaa;
        return rom[addr];
    }

    virtual void write(uint16_t addr, uint8_t data)
    {
    }
};

class CartMBC3 : public Cartridge
{
    // TODO: RTC, disabling extram
protected:
    uint8_t rom_bank, ram_bank;
    size_t ram_size;
    uint8_t *ram;
public:
    CartMBC3(size_t rom_size, uint8_t *rom_data)
        : Cartridge(rom_size, rom_data),
          rom_bank(1), ram_bank(0)
    {
        uint8_t cart_ram_size = rom_data[ROMHDR_RAM_SIZE];
        switch (cart_ram_size) {
        case 0: ram_size =   0 * 1024; break;
        case 1: ram_size =   2 * 1024; break;
        case 2: ram_size =   8 * 1024; break;
        case 3: ram_size =  32 * 1024; break;
        case 4: ram_size = 128 * 1024; break;
        case 5: ram_size =  64 * 1024; break;
        default:
            fprintf(stderr, "Unsupported RAM size %#02x\n", cart_ram_size);
            exit(1);
        }

        ram = NULL;
        if (ram_size)
            ram = (uint8_t *)calloc(ram_size, 1);
    }

    virtual uint8_t read(uint16_t addr)
    {
        if (addr < 0x4000)
            return rom[addr];
        else if (addr < 0x8000)
            return rom[addr - 0x4000 + rom_bank * ROMBANK_SIZE];
        else if (addr >= 0xA000 && addr < 0xC000)
            return ram[addr - 0xA000 + ram_bank * RAMBANK_SIZE];
        return 0xaa;
    }

    virtual void write(uint16_t addr, uint8_t data)
    {
        if (addr >= 0x2000 && addr < 0x4000) {
            printf("rom bank %#02x\n", data);
            rom_bank = data & 0x7f;
            // TODO truncate
            if (rom_bank == 0)
                rom_bank = 1;
        } else if (addr >= 0x4000 && addr < 0x6000) {
            if (data <= 3)
                ram_bank = data;
            // TODO RTC
        }
    }
};

int read_file(char *filename, uint8_t **buf, size_t *size)
{
    FILE *fp;

    fp = fopen(filename, "rb");
    if (!fp) {
        fprintf(stderr, "Failed to load file (\"%s\").\n", filename);
        return 1;
    }

    /* Get the file size */
    fseek(fp, 0L, SEEK_END);
    size_t allocsize = ftell(fp) * sizeof(uint8_t);
    rewind(fp);

    *buf = (uint8_t *)malloc(allocsize);
    if (*buf == NULL) {
        fprintf(stderr,
                "Error allocating mem for file (file=%s, size=%zu byte).",
                filename, allocsize);
        fclose(fp);
        return 1;
    }
    *size = fread(*buf, sizeof(uint8_t), allocsize, fp);
    fclose(fp);
    return 0;
}

Cartridge *load_rom(char *filename)
{
    uint8_t *rom;
    size_t rom_size;
    if (read_file(filename, &rom, &rom_size))
        exit(1);

    uint8_t cart_type = rom[ROMHDR_CART_TYPE];
    switch (cart_type) {
    case CART_TYPE_ROMONLY:
        return new CartRomOnly(rom_size, rom);
    case CART_TYPE_MBC3_RAM_BAT:
        return new CartMBC3(rom_size, rom);
    default:
        fprintf(stderr, "Unsupported cart type %#02x\n", cart_type);
        exit(1);
    }
    return NULL;
}

#define BIT(val, bitpos) (((val) >> (bitpos)) & 1)

void dump_state(Vmain *top)
{
    printf(" PC   SP   AF   BC   DE   HL  ZNHC\n"
            "%04x %04x %04x %04x %04x %04x %d%d%d%d\n\n",
            top->dbg_pc, top->dbg_sp, top->dbg_AF, top->dbg_BC,
            top->dbg_DE, top->dbg_HL,
            BIT(top->dbg_AF, 7), BIT(top->dbg_AF, 6),
            BIT(top->dbg_AF, 5), BIT(top->dbg_AF, 4));
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);

    gui_init(RES_X, RES_Y, ZOOM, "gb-fpga");
    uint8_t *pixbuf = (uint8_t*)calloc(RES_X * RES_Y, 1);

    MemRegion vram(0x8000, 0xA000);
    MemRegion wram(0xC000, 0xE000);
    Cartridge *cart = load_rom(argv[1]);;

    Vmain *top = new Vmain;

    top->reset = 1;
    top->clk = 0;
    top->eval();
    top->clk = 1;
    top->eval();
    top->reset = 0;
    top->clk = 0;
    top->eval();

    struct gui_input input_state = { 0 };
    bool vblank_old = 0;
    bool paused = 0;

    steady_clock::time_point last_poll = steady_clock::now();
    while (!Verilated::gotFinish()) {
        steady_clock::time_point now = steady_clock::now();
        auto ms_since_poll = duration_cast<milliseconds>(now - last_poll).count();
        if (ms_since_poll > 16) { // ~60 times per second
            last_poll = now;
            gui_input_poll(&input_state);
            if (input_state.special_quit)
                break;
            if (input_state.special_pause) {
                paused = !paused;
                printf("Paused: %d\n", paused);
            }
        }

        if (paused)
            continue;

        cart->update(top->extbus_addr, top->extbus_do_write, top->extbus_data_w, &top->extbus_data_r);
        wram.update(top->extbus_addr, top->extbus_do_write, top->extbus_data_w, &top->extbus_data_r);
        vram.update(top->vram_addr, top->vram_do_write, top->vram_data_w, &top->vram_data_r);

        top->joy_btn_a = input_state.button_a;
        top->joy_btn_b = input_state.button_b;
        top->joy_btn_start = input_state.button_start;
        top->joy_btn_select = input_state.button_select;
        top->joy_btn_up = input_state.button_up;
        top->joy_btn_down = input_state.button_down;
        top->joy_btn_left = input_state.button_left;
        top->joy_btn_right = input_state.button_right;

        top->clk = !top->clk;

        top->eval();

#ifdef DEBUG
        if (top->clk == 1 && top->dbg_instruction_retired)
            dump_state(top);
#endif

        // Redraw screen on vblank
        if (top->lcd_vblank && !vblank_old)
            gui_render_frame(pixbuf);
        vblank_old = top->lcd_vblank;

        if (top->clk && top->lcd_write)
            pixbuf[top->lcd_x + top->lcd_y * RES_X] = top->lcd_col;

        if (top->dbg_instruction_retired && top->dbg_halted) {
            printf("CPU halted, exiting\n");
            break;
        }
    }

    dump_state(top);

    top->final();

    delete top;

    return 0;
}
