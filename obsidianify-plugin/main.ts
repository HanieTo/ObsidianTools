import { App, Plugin, PluginSettingTab, Setting, TFile, TFolder, Modal, Notice, normalizePath, moment } from 'obsidian';

interface ObsidianifySettings {
	inboxPath: string;
}

const DEFAULT_SETTINGS: ObsidianifySettings = {
	inboxPath: 'Inbox'
}

// ---- Line classifiers (ported from ObsidianifyNote.ps1's Format-NoteBody) ----
const IP_REGEX = /^(\d{1,3}\.){3}\d{1,3}$/;
const DOMAIN_REGEX = /^[A-Za-z0-9][A-Za-z0-9.\-]*\.[A-Za-z]{2,}$/;
const PATH_REGEX = /^(\/[^\s]+|[A-Za-z]:\\[^\s]+)$/;
const PROMPT_REGEX = /^[\w.\-]+@[\w.\-]+:\S*[#$]/;
const COMMAND_WORDS = 'zmprov|grep|ssh|mount|ls|touch|dmesg|bash|openssl|curl|git|npm|docker|sudo|cd|cat|chmod|chown|systemctl|journalctl|ping|traceroute|nslookup|dig|yum|apt-get|apt|netstat|ss|ip|ifconfig|tail|head|vim|nano|ps|kill|df|du|tar|scp|rsync|wget|python3?|pip3?|vssadmin|powershell|reg|sc|tasklist|taskkill|iptables|firewall-cmd';
const COMMAND_REGEX = new RegExp(`^(${COMMAND_WORDS})\\b`);
const LABEL_REGEX = /^(.{1,60}):$/;

// Heuristic reformatting: wraps commands/IPs/paths in code, turns "Label:" lines
// into "## Label" sub-headings. Best-effort only.
function formatNoteBody(content: string): string {
	const blocks = content.trim().split(/(?:\r?\n){2,}/);
	const renderedBlocks: string[] = [];

	for (const block of blocks) {
		const lines = block.split(/\r?\n/);
		const outLines: string[] = [];
		let codeBuffer: string[] = [];

		const flushCode = () => {
			if (codeBuffer.length > 0) {
				outLines.push('```', ...codeBuffer, '```');
				codeBuffer = [];
			}
		};

		for (const line of lines) {
			const trimmed = line.trim();

			if (trimmed === '') {
				flushCode();
				outLines.push('');
				continue;
			}

			const labelMatch = trimmed.match(LABEL_REGEX);
			if (labelMatch && !COMMAND_REGEX.test(trimmed)) {
				flushCode();
				outLines.push(`## ${labelMatch[1].trim()}`);
				continue;
			}

			if (COMMAND_REGEX.test(trimmed) || PROMPT_REGEX.test(trimmed)) {
				codeBuffer.push(trimmed);
				continue;
			}

			flushCode();

			if (IP_REGEX.test(trimmed) || DOMAIN_REGEX.test(trimmed) || PATH_REGEX.test(trimmed)) {
				outLines.push(`\`${trimmed}\``);
			} else {
				outLines.push(trimmed);
			}
		}

		flushCode();
		renderedBlocks.push(outLines.join('\n'));
	}

	return renderedBlocks.join('\n\n');
}

function safeFileName(name: string): string {
	return name.replace(/[\\/:*?"<>|]/g, '-').trim();
}

class CategoryModal extends Modal {
	result: string | null = null;
	private submitted = false;
	private onSubmit: (category: string | null) => void;
	private categories: string[];
	private fileLabel: string;

	constructor(app: App, fileLabel: string, categories: string[], onSubmit: (category: string | null) => void) {
		super(app);
		this.fileLabel = fileLabel;
		this.categories = categories;
		this.onSubmit = onSubmit;
	}

	onOpen() {
		const { contentEl } = this;
		contentEl.createEl('h3', { text: 'Choose a category' });
		contentEl.createEl('p', { text: this.fileLabel });

		const input = contentEl.createEl('input', {
			type: 'text',
			attr: { list: 'obsidianify-categories', placeholder: 'Type or pick a category...' }
		});
		input.style.width = '100%';

		const datalist = contentEl.createEl('datalist');
		datalist.id = 'obsidianify-categories';
		for (const c of this.categories) {
			datalist.createEl('option', { value: c });
		}

		input.focus();

		const buttonRow = contentEl.createDiv();
		buttonRow.style.marginTop = '1em';
		buttonRow.style.display = 'flex';
		buttonRow.style.justifyContent = 'flex-end';
		buttonRow.style.gap = '0.5em';

		const skipBtn = buttonRow.createEl('button', { text: 'Skip this file' });
		skipBtn.onclick = () => {
			this.result = null;
			this.close();
		};

		const okBtn = buttonRow.createEl('button', { text: 'OK', cls: 'mod-cta' });
		okBtn.onclick = () => {
			this.result = input.value.trim();
			this.close();
		};

		input.addEventListener('keydown', (e) => {
			if (e.key === 'Enter') {
				this.result = input.value.trim();
				this.close();
			}
		});
	}

	onClose() {
		this.contentEl.empty();
		if (!this.submitted) {
			this.submitted = true;
			this.onSubmit(this.result);
		}
	}
}

export default class ObsidianifyPlugin extends Plugin {
	settings: ObsidianifySettings;
	private processingFiles: Set<string> = new Set();

	async onload() {
		await this.loadSettings();

		this.addCommand({
			id: 'process-inbox',
			name: 'Process Inbox folder',
			callback: () => this.processInbox()
		});

		this.addRibbonIcon('inbox', 'Process Obsidianify Inbox', () => this.processInbox());

		this.addSettingTab(new ObsidianifySettingTab(this.app, this));

		// Auto-prompt when a new .txt lands in the Inbox folder (e.g. via a
		// mobile share-sheet, or dragging a file in on desktop).
		this.registerEvent(this.app.vault.on('create', (file) => {
			if (file instanceof TFile && file.extension === 'txt' && this.isInInbox(file)) {
				setTimeout(() => this.processFile(file), 300);
			}
		}));
	}

	isInInbox(file: TFile): boolean {
		const inbox = normalizePath(this.settings.inboxPath);
		return file.parent?.path === inbox;
	}

	getExistingCategories(): string[] {
		const root = this.app.vault.getRoot();
		const categories: string[] = [];
		for (const child of root.children) {
			if (child instanceof TFolder && child.name !== this.settings.inboxPath && !child.name.startsWith('.')) {
				categories.push(child.name);
			}
		}
		return categories.sort();
	}

	async processInbox() {
		const inboxPath = normalizePath(this.settings.inboxPath);
		const inboxFolder = this.app.vault.getAbstractFileByPath(inboxPath);

		if (!(inboxFolder instanceof TFolder)) {
			new Notice(`Inbox folder "${this.settings.inboxPath}" not found.`);
			return;
		}

		const txtFiles = inboxFolder.children.filter(
			(f): f is TFile => f instanceof TFile && f.extension === 'txt'
		);

		if (txtFiles.length === 0) {
			new Notice('No .txt files in Inbox.');
			return;
		}

		let created = 0, skipped = 0, failed = 0;

		for (const file of txtFiles) {
			const result = await this.processFile(file);
			if (result === 'created') created++;
			else if (result === 'skipped') skipped++;
			else if (result === 'failed') failed++;
			// 'busy' results (already being processed elsewhere) are not counted
		}

		new Notice(`Obsidianify: ${created} created, ${skipped} skipped, ${failed} failed.`);
	}

	async processFile(file: TFile): Promise<'created' | 'skipped' | 'failed' | 'busy'> {
		if (this.processingFiles.has(file.path)) {
			return 'busy';
		}
		this.processingFiles.add(file.path);

		try {
			const categories = this.getExistingCategories();

			const category = await new Promise<string | null>((resolve) => {
				new CategoryModal(this.app, file.name, categories, resolve).open();
			});

			if (category === null) {
				return 'skipped';
			}

			const content = await this.app.vault.read(file);
			const rawTitle = file.basename;
			const safeTitle = safeFileName(rawTitle);
			const body = formatNoteBody(content);
			const createdAt = moment().format('YYYY-MM-DDTHH:mm:ss');

			let destDir = '';
			let tagsLine = 'tags: []';
			if (category !== '') {
				const safeCategory = safeFileName(category);
				destDir = safeCategory;
				tagsLine = `tags: [${safeCategory}]`;
				const destDirPath = normalizePath(destDir);
				if (!this.app.vault.getAbstractFileByPath(destDirPath)) {
					await this.app.vault.createFolder(destDirPath);
				}
			}

			const frontmatter = `---\ntitle: "${rawTitle}"\ncreated: ${createdAt}\naliases: []\n${tagsLine}\nsource: "${file.name}"\nsummary: ""\n---\n\n# ${rawTitle}\n\n---\n\n`;

			const destPath = await this.getUniquePath(destDir, safeTitle, '.md');
			await this.app.vault.create(destPath, frontmatter + body);

			const processedDir = `${this.settings.inboxPath}/Processed`;
			const processedDirPath = normalizePath(processedDir);
			if (!this.app.vault.getAbstractFileByPath(processedDirPath)) {
				await this.app.vault.createFolder(processedDirPath);
			}
			const processedPath = await this.getUniquePath(processedDir, safeTitle, '.txt');
			await this.app.vault.rename(file, processedPath);

			return 'created';
		} catch (e) {
			new Notice(`Failed to convert ${file.name}: ${e}`);
			return 'failed';
		} finally {
			this.processingFiles.delete(file.path);
		}
	}

	async getUniquePath(dir: string, baseName: string, ext: string): Promise<string> {
		let candidate = normalizePath(dir ? `${dir}/${baseName}${ext}` : `${baseName}${ext}`);
		let i = 2;
		while (this.app.vault.getAbstractFileByPath(candidate)) {
			candidate = normalizePath(dir ? `${dir}/${baseName} (${i})${ext}` : `${baseName} (${i})${ext}`);
			i++;
		}
		return candidate;
	}

	async loadSettings() {
		this.settings = Object.assign({}, DEFAULT_SETTINGS, await this.loadData());
	}

	async saveSettings() {
		await this.saveData(this.settings);
	}
}

class ObsidianifySettingTab extends PluginSettingTab {
	plugin: ObsidianifyPlugin;

	constructor(app: App, plugin: ObsidianifyPlugin) {
		super(app, plugin);
		this.plugin = plugin;
	}

	display(): void {
		const { containerEl } = this;
		containerEl.empty();

		new Setting(containerEl)
			.setName('Inbox folder')
			.setDesc('Vault folder to watch for .txt files. Save or share files into this folder to convert them into notes.')
			.addText(text => text
				.setPlaceholder('Inbox')
				.setValue(this.plugin.settings.inboxPath)
				.onChange(async (value) => {
					this.plugin.settings.inboxPath = value || 'Inbox';
					await this.plugin.saveSettings();
				}));
	}
}
