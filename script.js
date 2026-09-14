// =================================================================================
// Beis Anytime - Application Logic
// =================================================================================

// --- Lazy Loading ---
const imageObserver = new IntersectionObserver((entries, observer) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            const img = entry.target;
            if (img.dataset.src) {
                img.src = img.dataset.src;
                img.removeAttribute('data-src');
                observer.unobserve(img);
            }
        }
    });
}, { rootMargin: '200px' });

// --- Google Auth ---
const GOOGLE_CLIENT_ID = '248585696121-67ecvsoqhtbpc0b2qt5f486864p0uvnq.apps.googleusercontent.com';

const decodeBase64Url = (value) => {
    const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
    return decodeURIComponent(atob(normalized).split('').map(char => `%${('00' + char.charCodeAt(0).toString(16)).slice(-2)}`).join(''));
};

window.handleCredentialResponse = (response) => {
    try {
        if (!response || !response.credential) throw new Error('Google returned no credential');
        const parts = response.credential.split('.');
        if (parts.length !== 3) throw new Error('Invalid Google credential');
        const payload = JSON.parse(decodeBase64Url(parts[1]));
        if (!payload.email || payload.email_verified === false) throw new Error('Google account email is not verified');

        const user = {
            name: payload.name || payload.email,
            email: payload.email,
            picture: payload.picture || ''
        };
        localStorage.setItem('googleUser', JSON.stringify(user));
        window.dispatchEvent(new CustomEvent('google-signin-success', { detail: user }));
    } catch (error) {
        console.error('Google sign-in failed:', error);
        const message = error instanceof Error ? error.message : 'Unable to sign in with Google';
        window.dispatchEvent(new CustomEvent('google-signin-error', { detail: message }));
    }
};

const initializeGoogleSignIn = () => {
    if (!window.google || !window.google.accounts || !window.google.accounts.id) return false;
    window.google.accounts.id.initialize({
        client_id: GOOGLE_CLIENT_ID,
        callback: window.handleCredentialResponse,
        auto_select: false,
        cancel_on_tap_outside: true,
        use_fedcm_for_prompt: true
    });

    const button = document.getElementById('google-signin-button');
    if (button) {
        window.google.accounts.id.renderButton(button, {
            type: 'icon',
            shape: 'circle',
            theme: 'outline',
            size: 'large'
        });
    }
    return true;
};

const startGoogleSignIn = () => {
    if (initializeGoogleSignIn()) {
        window.google.accounts.id.prompt();
        return;
    }
    showToast('Google Sign-In is still loading. Please try again.', 'error');
    let attempts = 0;
    const retry = setInterval(() => {
        attempts += 1;
        if (initializeGoogleSignIn() || attempts >= 20) clearInterval(retry);
    }, 250);
};

document.addEventListener('DOMContentLoaded', () => {
    // --- Configuration ---
    // 0. API for Video Metadata & Uploads (New R2-based worker)

    // 1. API for Community Feed (The new D1 Worker)
    const COMMUNITY_API_URL = 'https://beis-social-worker.beisanytime.workers.dev'; // UPDATE THIS!

    // 2. API for Video Likes/Comments (The original KV Worker)
    const VIDEO_API_URL = 'https://beis-anytime-viewsapi.beisanytime.workers.dev';

    const ADMIN_EMAILS = ['beisanytime@gmail.com', 'joshuacalvert1@gmail.com'];
    const MAIN_API_URL = 'https://beis-api.beisanytime.workers.dev';

    // --- State ---
    let allShiurimCache = [];
    let currentUser = null;
    let capturedThumbnailDataUrl = null;

    // --- DOM ---
    const contentArea = document.getElementById('app-content');
    const navItems = document.querySelectorAll('.nav-item, .bottom-nav-item');
    const themeToggle = document.getElementById('theme-toggle');
    const mobileThemeToggle = document.getElementById('mobile-theme-toggle');

    // --- Helpers ---
    const applyTheme = (theme) => {
        document.documentElement.setAttribute('data-theme', theme);
        localStorage.setItem('theme', theme);
        if (themeToggle) themeToggle.querySelector('i').className = theme === 'dark' ? 'fas fa-sun' : 'fas fa-moon';
        if (mobileThemeToggle) mobileThemeToggle.querySelector('i').className = theme === 'dark' ? 'fas fa-sun' : 'fas fa-moon';
    };

    const formatRabbiName = (id) => {
        if (!id) return 'Unknown';
        if (id.toLowerCase() === 'guests') return 'Guest Speakers';
        if (id.toLowerCase() === 'time4mishna') return 'Time4Mishna';
        return id.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
    };

    const timeAgo = (date) => {
        const seconds = Math.floor((new Date() - date) / 1000);
        if (seconds < 60) return 'Just now';
        const minutes = Math.floor(seconds / 60);
        if (minutes < 60) return `${minutes}m ago`;
        const hours = Math.floor(minutes / 60);
        if (hours < 24) return `${hours}h ago`;
        const days = Math.floor(hours / 24);
        if (days < 7) return `${days}d ago`;
        return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: days > 365 ? 'numeric' : undefined });
    };

    const fetchMain = async (endpoint, options = {}) => {
        try {
            const res = await fetch(`${MAIN_API_URL}${endpoint}`, options);
            if (!res.ok) throw new Error('API Error');
            if (res.status === 204) return null;
            return await res.json();
        } catch (e) { console.error(e); return null; }
    };

    // Generic Fetcher for the two worker APIs
    const workerFetch = async (baseUrl, endpoint, options = {}) => {
        try {
            const res = await fetch(`${baseUrl}${endpoint}`, options);
            if (!res.ok) throw new Error('Worker Error');
            if (res.status === 204) return null;
            return await res.json();
        } catch (e) { return null; }
    };

    // --- Password helpers (stored in sessionStorage, validated server-side) ---
    const getStoredPassword = () => sessionStorage.getItem('uploadPassword');
    const setStoredPassword = (pwd) => sessionStorage.setItem('uploadPassword', pwd);

    // Authenticated fetch for admin endpoints (sends password + Google email)
    const fetchAdmin = async (endpoint, options = {}) => {
        const password = getStoredPassword();
        if (!password) {
            renderPasswordModal('admin');
            return null;
        }
        const headers = { ...options.headers, 'X-Upload-Password': password };
        if (currentUser) {
            headers['X-User-Email'] = currentUser.email;
            headers['X-User-Name'] = currentUser.name;
        }
        try {
            const res = await fetch(`${MAIN_API_URL}${endpoint}`, { ...options, headers });
            if (res.status === 401) {
                sessionStorage.removeItem('uploadPassword');
                renderPasswordModal('admin');
                return null;
            }
            if (!res.ok) throw new Error('API Error');
            if (res.status === 204) return null;
            return await res.json();
        } catch (e) { console.error(e); return null; }
    };

    // Upload multipart chunks concurrently, but keep a bounded number of requests active.
    // R2 completion still requires every part in ascending part-number order.
    const uploadMultipartParts = async ({ file, r2Key, uploadId, headers, concurrency = 4, onProgress }) => {
        const CHUNK_SIZE = 10 * 1024 * 1024;
        const totalParts = Math.max(1, Math.ceil(file.size / CHUNK_SIZE));
        const uploadedParts = new Array(totalParts);
        let nextPartIndex = 0;
        let completedParts = 0;

        const uploadNextPart = async () => {
            while (true) {
                const partIndex = nextPartIndex++;
                if (partIndex >= totalParts) return;

                const partNumber = partIndex + 1;
                const chunk = file.slice(
                    partIndex * CHUNK_SIZE,
                    Math.min((partIndex + 1) * CHUNK_SIZE, file.size)
                );
                const partURL = `${MAIN_API_URL}/api/admin/upload-part?key=${encodeURIComponent(r2Key)}&uploadId=${encodeURIComponent(uploadId)}&partNumber=${partNumber}`;
                const partResponse = await fetch(partURL, {
                    method: 'PUT',
                    body: chunk,
                    headers
                });
                const partData = await partResponse.json();

                if (!partResponse.ok || partData.error || !partData.etag) {
                    throw new Error(partData.error || `Failed to upload part ${partNumber}`);
                }

                uploadedParts[partIndex] = {
                    partNumber: partData.partNumber,
                    etag: partData.etag
                };
                completedParts += 1;
                if (onProgress) onProgress(completedParts, totalParts);
            }
        };

        await Promise.all(
            Array.from({ length: Math.min(concurrency, totalParts) }, uploadNextPart)
        );

        return uploadedParts;
    };

    // --- Toast Helper ---
    const captureFirstFrame = (videoUrl) => new Promise((resolve, reject) => {
        const video = document.createElement('video');
        video.muted = true;
        video.playsInline = true;
        video.preload = 'auto';
        video.crossOrigin = 'anonymous';
        const timeout = setTimeout(() => { cleanup(); reject(new Error('Timed out loading video')); }, 10000);
        const cleanup = () => {
            clearTimeout(timeout);
            video.pause();
            video.removeAttribute('src');
            video.load();
        };
        video.onerror = () => {
            const code = video.error?.code;
            cleanup();
            reject(new Error(code ? `Video could not be loaded (media error ${code})` : 'Video could not be loaded'));
        };
        video.onloadeddata = () => {
            try {
                const canvas = document.createElement('canvas');
                canvas.width = video.videoWidth;
                canvas.height = video.videoHeight;
                if (!canvas.width || !canvas.height) throw new Error('Video has no dimensions');
                canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
                const frame = canvas.toDataURL('image/jpeg', 0.85);
                cleanup();
                resolve(frame);
            } catch (error) {
                cleanup();
                reject(error);
            }
        };
        video.src = videoUrl;
    });

    const showToast = (message, type = 'success') => {
        const container = document.getElementById('toast-container');
        const toast = document.createElement('div');
        toast.className = `toast toast-${type}`;
        toast.innerHTML = `
            <div class="toast-content">${message}</div>
        `;
        container.appendChild(toast);
        setTimeout(() => {
            toast.classList.add('hiding');
            setTimeout(() => toast.remove(), 300);
        }, 3000);
    };

    // --- Bookmark Logic ---
    const getBookmarks = () => JSON.parse(localStorage.getItem('bookmarks') || '[]');
    const isBookmarked = (id) => getBookmarks().includes(id);
    const toggleBookmark = (id, e) => {
        if (e) { e.preventDefault(); e.stopPropagation(); }
        let marks = getBookmarks();
        if (marks.includes(id)) {
            marks = marks.filter(m => m !== id);
            showToast('Removed from Watch Later', 'success');
        } else {
            marks.push(id);
            showToast('Added to Watch Later', 'success');
        }
        localStorage.setItem('bookmarks', JSON.stringify(marks));
        // Refresh UI if on bookmarks page
        if (document.body.getAttribute('data-page-context') === 'bookmarks') loadPage('bookmarks');
        else if (e) {
            const btn = e.target.closest('.bookmark-btn');
            if (btn) btn.classList.toggle('active');
        }
    };

    const checkLatestPost = async () => {
        try {
            const posts = await workerFetch(COMMUNITY_API_URL, '/api/posts');
            if (posts && posts.length > 0) {
                const latest = posts[0];
                const lastId = localStorage.getItem('lastSeenPostId');
                if (lastId != latest.id.toString()) {
                    document.getElementById('community-badge').style.display = 'block';
                    document.getElementById('community-badge-mobile').style.display = 'block';
                    showPostNotification(latest);
                }
            }
        } catch (e) { console.error("Notif error:", e); }
    };

    // --- Search Logic ---
    const filterAllPage = (query) => {
        const grid = document.querySelector('.grid-videos');
        if (!grid) return;

        const filtered = allShiurimCache.filter(s => {
            const q = query.toLowerCase();
            return (s.title && s.title.toLowerCase().includes(q)) ||
                (s.rabbi && s.rabbi.toLowerCase().replace('_', ' ').includes(q)) ||
                (s.description && s.description.toLowerCase().includes(q));
        });

        if (filtered.length === 0) {
            grid.innerHTML = renderEmptyState(`No results for "${query}"`);
        } else {
            renderVideoGrid(filtered, grid);
        }
    };

    // --- Global Search Listener ---
    const searchInput = document.getElementById('globalSearch');
    if (searchInput) {
        searchInput.addEventListener('input', (e) => {
            const query = e.target.value.trim();
            // If user types, ensure we are on 'all' page or specific search view
            if (query.length > 0 && document.body.getAttribute('data-page-context') !== 'all') {
                loadPage('all');
            }
            // If on 'all' page, filter immediately
            if (document.body.getAttribute('data-page-context') === 'all') {
                // If query is empty, show all. If has text, filter.
                if (query.length === 0) {
                    renderVideoGrid(allShiurimCache, document.querySelector('.grid-videos'));
                } else {
                    filterAllPage(query);
                }
            }
        });
    }

    const showPostNotification = (post) => {
        const toast = document.createElement('div');
        toast.className = 'post-notification';
        toast.innerHTML = `
            <div class="notification-header">
                <img src="${post.avatar_url}" class="notif-avatar">
                <div class="notif-info">
                    <strong>Latest Announcement</strong>
                    <span>${post.display_name}</span>
                </div>
                <button class="notif-close">&times;</button>
            </div>
            <div class="notif-body">${post.content.length > 100 ? post.content.substring(0, 97) + '...' : post.content}</div>
            <button class="btn-notif" onclick="loadPage('community'); this.parentElement.classList.add('hide'); setTimeout(()=>this.parentElement.remove(), 300);">Read Full Post</button>
        `;
        document.body.appendChild(toast);
        toast.querySelector('.notif-close').onclick = () => {
            toast.classList.add('hide');
            setTimeout(() => toast.remove(), 300);
        };
        setTimeout(() => { if (toast.parentElement) { toast.classList.add('hide'); setTimeout(() => toast.remove(), 300); } }, 10000);
    };

    const getAllShiurim = async (force = false) => {
        if (!force) {
            if (allShiurimCache.length > 0) return allShiurimCache;
            const cached = sessionStorage.getItem('allShiurim');
            if (cached) {
                allShiurimCache = JSON.parse(cached);
                return allShiurimCache;
            }
        }

        try {
            const data = await fetchMain('/api/all-shiurim', { cache: 'no-store' });
            if (data) {
                data.sort((a, b) => new Date(b.date || 0) - new Date(a.date || 0));
                allShiurimCache = data;
                try { sessionStorage.setItem('allShiurim', JSON.stringify(data)); } catch (e) { }
            }
            return data;
        } catch (e) { console.error('Failed to fetch shiurim', e); return []; }
    };

    // --- Components Renderers ---
    const renderEmptyState = (msg) => `
<div class="empty-state">
    <div class="empty-icon"><i class="fas fa-search"></i></div>
    <h3>No Items Found</h3>
    <p style="color:var(--text-muted);">${msg}</p>
</div>
`;

    const renderVideoGrid = (videos, container) => {
        if (!videos || videos.length === 0) {
            container.innerHTML = renderEmptyState("Try checking back later.");
            return;
        }
        const frag = document.createDocumentFragment();
        videos.forEach(v => {
            const card = document.createElement('a');
            card.href = '#';
            card.className = 'video-card';
            card.dataset.shiurId = v.id;
            if (v.rabbi) card.setAttribute('data-rabbi', v.rabbi);

            const isTime4Mishna = v.rabbi && v.rabbi.toLowerCase() === 'time4mishna';
            const thumb = isTime4Mishna ? 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?auto=format&fit=crop&q=80&w=1000' : (v.thumbnailDataUrl || v.thumbnailUrl || '');
            const progress = parseFloat(localStorage.getItem(`vid_progress_${v.id}`) || 0);
            const duration = parseFloat(localStorage.getItem(`vid_duration_${v.id}`) || 0);
            const percent = (progress && duration) ? (progress / duration) * 100 : 0;
            const bookmarked = isBookmarked(v.id);

            card.innerHTML = `
        <div class="thumb-wrapper">
            <img data-src="${thumb}" class="thumb-img" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 9' fill='%23f3f4f6'%3E%3C/svg%3E" alt="Thumbnail" loading="lazy">
            <div class="rabbi-badge">
                <span class="rabbi-dot"></span>
                ${formatRabbiName(v.rabbi)}
            </div>
            ${percent > 0 ? `
                <div class="progress-bar-container">
                    <div class="progress-bar-fill" style="width: ${percent}%"></div>
                </div>
            ` : ''}
            <button class="bookmark-btn ${bookmarked ? 'active' : ''}" title="Watch Later">
                <i class="${bookmarked ? 'fas' : 'far'} fa-bookmark"></i>
            </button>
        </div>
        <div class="card-content">
            <h3 class="card-title">${v.title}</h3>
            ${v.tags ? v.tags.map(t => `<span class="tag-badge">${t}</span>`).join('') : ''}
            <span class="card-date">${v.date ? new Date(v.date).toLocaleDateString() : ''}</span>
        </div>
    `;
            const btn = card.querySelector('.bookmark-btn');
            if (btn) btn.onclick = (e) => toggleBookmark(v.id, e);
            frag.appendChild(card);
        });
        container.innerHTML = '';
        container.appendChild(frag);
        container.querySelectorAll('img[data-src]').forEach(img => imageObserver.observe(img));
    };

    // --- Page Logic ---
    const pages = {
        home: async () => {
            const data = await getAllShiurim();
            if (!data) return;
            const recent = data.slice(0, 8);

            // Calculate "Continue Watching"
            const continuing = data.filter(v => {
                const prog = parseFloat(localStorage.getItem(`vid_progress_${v.id}`) || 0);
                const dur = parseFloat(localStorage.getItem(`vid_duration_${v.id}`) || 0);
                return prog > 10 && (prog < dur - 10); // More than 10s watched, more than 10s left
            }).slice(0, 5);

            contentArea.innerHTML = `
        <section class="hero-card">
            <h1>Hasmo Beis, Anytime, Anywhere.</h1>
            <p style="max-width: 600px; font-size: 1.1rem; opacity: 0.8;">Explore a vast library of Shiurim from our esteemed Rabbis. Watch, listen, and grow.</p>
            <div class="hero-actions">
                <button class="btn btn-primary" onclick="loadPage('all')">Browse Library</button>
            </div>
        </section>

        ${continuing.length > 0 ? `
            <h2 style="margin-bottom: 24px;">Continue Watching</h2>
            <div class="continue-watching-tray" id="continueTray"></div>
        ` : ''}

        <h2 style="margin-bottom: 24px;">Latest Shiurim</h2>
        <div class="grid-videos"></div>
    `;
            if (continuing.length > 0) renderVideoGrid(continuing, contentArea.querySelector('#continueTray'));
            renderVideoGrid(recent, contentArea.querySelector('.grid-videos'));
        },

        all: async () => {
            const data = await getAllShiurim();
            contentArea.innerHTML = `
                <div class="mobile-search-container">
                    <div class="search-wrapper">
                        <i class="fas fa-search"></i>
                        <input type="text" id="mobileSearch" class="search-input" placeholder="Search shiurim..." value="${document.getElementById('globalSearch')?.value || ''}">
                    </div>
                </div>
                <h1 style="margin-bottom:30px;">All Shiurim</h1>
                <div class="grid-videos"></div>
            `;

            // Link mobile search to global search
            const mSearch = document.getElementById('mobileSearch');
            if (mSearch) {
                mSearch.oninput = (e) => {
                    const val = e.target.value;
                    const gSearch = document.getElementById('globalSearch');
                    if (gSearch) gSearch.value = val;
                    filterAllPage(val);
                };
            }

            const searchVal = document.getElementById('globalSearch')?.value.trim();
            if (searchVal) {
                filterAllPage(searchVal);
            } else {
                renderVideoGrid(data, contentArea.querySelector('.grid-videos'));
            }
        },

        bookmarks: async () => {
            const marks = getBookmarks();
            const data = await getAllShiurim();
            const filtered = data.filter(s => marks.includes(s.id));
            contentArea.innerHTML = `<h1 style="margin-bottom:30px;">Watch Later</h1><div class="grid-videos"></div>`;
            renderVideoGrid(filtered, contentArea.querySelector('.grid-videos'));
        },

        community: async () => {
            const isAdmin = currentUser && ADMIN_EMAILS.includes(currentUser.email);

            contentArea.innerHTML = `
        <div class="feed-container">
            <div class="feed-header">
                <div>
                    <h1>Community Feed</h1>
                    <p class="feed-subtitle">Official announcements and updates from the Beis Anytime team</p>
                </div>
                <button class="btn btn-secondary feed-refresh-btn" onclick="loadPage('community')"><i class="fas fa-sync"></i> Refresh</button>
            </div>

            ${isAdmin ? `
            <div class="post-composer">
                <div class="composer-header">
                    <img src="${currentUser.picture}" class="composer-avatar">
                    <span class="composer-label">Posting as admin</span>
                </div>
                <textarea id="postInput" class="composer-textarea" placeholder="Write an official announcement..." rows="3"></textarea>
                <div class="composer-footer">
                    <span class="composer-hint"><i class="fas fa-info-circle"></i> Visible to all community members</span>
                    <button id="postSubmitBtn" class="btn btn-primary"><i class="fas fa-paper-plane"></i> Post</button>
                </div>
            </div>
            ` : `
            <div class="feed-notice">
                <div class="feed-notice-icon"><i class="fas fa-bullhorn"></i></div>
                <div>
                    <strong>Official Announcements</strong>
                    <span>Updates and news from the Beis Anytime team</span>
                </div>
            </div>
            `}

            <div id="postsList" class="posts-grid">
                <div class="skeleton-post"></div>
                <div class="skeleton-post"></div>
            </div>
        </div>
    `;

            if (isAdmin) {
                document.getElementById('postSubmitBtn').onclick = async () => {
                    const txt = document.getElementById('postInput').value.trim();
                    if (!txt) return;

                    const btn = document.getElementById('postSubmitBtn');
                    btn.disabled = true;
                    btn.textContent = "Posting...";

                    await workerFetch(COMMUNITY_API_URL, '/api/posts', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ content: txt, user: currentUser })
                    });

                    loadPage('community');
                };
            }

            const posts = await workerFetch(COMMUNITY_API_URL, '/api/posts');
            const list = document.getElementById('postsList');

            if (posts && posts.length > 0) {
                localStorage.setItem('lastSeenPostId', posts[0].id.toString());
                document.getElementById('community-badge').style.display = 'none';
                document.getElementById('community-badge-mobile').style.display = 'none';
            }

            if (!posts || !posts.length) {
                list.innerHTML = renderEmptyState("No announcements yet.");
                return;
            }

            list.innerHTML = posts.map(p => `
        <div class="post-card">
            <div class="post-header">
                <img src="${p.avatar_url}" class="post-avatar">
                <div class="post-meta">
                    <span class="post-author">${p.display_name} <i class="fas fa-check-circle" style="color:var(--color-accent); font-size:0.75rem; margin-left:4px;" title="Verified Admin"></i></span>
                    <span class="post-time">${timeAgo(new Date(p.created_at * 1000))}</span>
                </div>
                ${(isAdmin) ? `
                    <button class="post-delete-btn" onclick="deletePost(${p.id})" title="Delete post"><i class="fas fa-trash-alt"></i></button>
                ` : ''}
            </div>
            <div class="post-content">${p.content}</div>
        </div>
    `).join('');

            window.deletePost = async (id) => {
                if (confirm('Delete post?')) {
                    await workerFetch(COMMUNITY_API_URL, `/api/posts/${id}`, { method: 'DELETE', headers: { 'X-User-Email': currentUser.email } });
                    loadPage('community');
                }
            };
        },

        speakers: async () => {
            const data = await getAllShiurim();
            const rabbisMap = new Map();

            data.forEach(s => {
                if (!s.rabbi) return;
                // Normalize key for grouping (e.g., "rabbi hartman" and "rabbi_hartman" group together)
                const normalized = s.rabbi.toLowerCase().replace(/_/g, ' ');
                if (!rabbisMap.has(normalized) && normalized !== 'time4mishna') {
                    rabbisMap.set(normalized, {
                        id: s.rabbi, // Keep original ID for the link
                        name: formatRabbiName(s.rabbi),
                        icon: normalized === 'guests' ? 'fa-users' : 'fa-user-tie'
                    });
                }
            });

            const speakers = Array.from(rabbisMap.values());
            speakers.sort((a, b) => {
                if (a.id.toLowerCase() === 'guests') return 1;
                if (b.id.toLowerCase() === 'guests') return -1;
                return a.name.localeCompare(b.name);
            });

            contentArea.innerHTML = `<h1 style="margin-bottom:30px;">Speakers</h1><div style="display:grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap:24px;" id="speakerGrid"></div>`;

            const grid = document.getElementById('speakerGrid');
            speakers.forEach(s => {
                const el = document.createElement('a');
                el.href = '#';
                el.className = 'video-card';
                el.style.alignItems = 'center';
                el.style.padding = '40px';
                el.style.textAlign = 'center';
                el.setAttribute('data-rabbi', s.id);
                el.innerHTML = `
            <div style="width:80px; height:80px; background:var(--bg-surface-hover); border-radius:50%; display:flex; align-items:center; justify-content:center; margin-bottom:16px; font-size:2rem; color:var(--text-muted);">
                <i class="fas ${s.icon}"></i>
            </div>
            <h3 style="margin:0;">${s.name}</h3>
        `;
                el.onclick = (e) => { e.preventDefault(); loadPage('speaker', { rabbi: s.id }); };
                grid.appendChild(el);
            });
        },

        time4mishna: async () => {
            const data = await getAllShiurim();
            const filtered = data.filter(s => s.rabbi && s.rabbi.toLowerCase() === 'time4mishna');

            // Check if user is authorized to upload
            const canUpload = currentUser && ADMIN_EMAILS.includes(currentUser.email) && getStoredPassword();

            contentArea.innerHTML = `
                 <div class="flex-between" style="margin-bottom: 30px;">
                     <div>
                         <h1>Time4Mishna</h1>
                         <p>${filtered.length} Shiurim available</p>
                     </div>
                     <button class="btn btn-primary" onclick="loadPage('upload_time4mishna')">
                        <i class="fas fa-upload"></i> Upload Mishna
                     </button>
                 </div>
                 <div class="grid-videos"></div>
             `;
            renderVideoGrid(filtered, contentArea.querySelector('.grid-videos'));
        },

        speaker: async (params) => {
            const data = await getAllShiurim();
            const normalizedParam = params.rabbi.toLowerCase().replace(/_/g, ' ');
            const filtered = data.filter(s => s.rabbi && s.rabbi.toLowerCase().replace(/_/g, ' ') === normalizedParam);
            contentArea.innerHTML = `
        <div style="margin-bottom: 30px;">
            <h1>${formatRabbiName(params.rabbi)}</h1>
            <p>${filtered.length} Shiurim available</p>
        </div>
        <div class="grid-videos"></div>
    `;
            renderVideoGrid(filtered, contentArea.querySelector('.grid-videos'));
        },

        view_shiur: async (params) => {
            // Reuse metadata already loaded by Up Next; fetch only when opened elsewhere.
            const shiur = params.preloadedShiur || await fetchMain(`/api/shiurim/id/${params.id}`);

            if (!shiur) {
                contentArea.innerHTML = renderEmptyState("Shiur unavailable.");
                return;
            }

            // Sync fresh data back to global cache
            const idx = allShiurimCache.findIndex(s => s.id === shiur.id);
            if (idx !== -1) allShiurimCache[idx] = shiur;
            else allShiurimCache.push(shiur);

            // 3. Render Player & Skeleton for 'Related'
            contentArea.innerHTML = `
        <div class="view-shiur-grid">
            <div class="main-video-column">
                <div class="flex-between" style="margin-bottom:20px;">
                    <button class="btn btn-secondary" onclick="window.history.back()">
                        <i class="fas fa-arrow-left"></i> Back
                    </button>
                    <div style="display:flex; gap:12px;">
                        <button class="btn btn-secondary" id="shareBtn" title="Share">
                            <i class="fas fa-share"></i> Share
                        </button>
                        ${!(shiur.rabbi && shiur.rabbi.toLowerCase() === 'time4mishna') ? `<button class="btn btn-secondary" id="cinemaToggle" title="Cinema Mode">
                            <i class="fas fa-expand"></i>
                        </button>` : ''}
                    </div>
                </div>

                <div class="video-container" id="player-container">
                    <div class="skeleton" style="width:100%; height:100%; position:absolute; top:0; left:0; z-index:0;"></div>
                    ${shiur.rabbi && shiur.rabbi.toLowerCase() === 'time4mishna'
                    ? `<div class="audio-player-card" id="audioCard" style="cursor:pointer; position:relative; z-index:1;" onclick="const a=document.getElementById('player-video'); a.paused ? a.play() : a.pause();">
                                <div class="audio-player-art">
                                    <i class="fas fa-headphones" id="audioPlayIcon"></i>
                                </div>
                                <div class="audio-player-info">
                                    <div class="audio-player-title">${shiur.title}</div>
                                    <div class="audio-player-rabbi">Time4Mishna</div>
                                </div>
                                <audio id="player-video" controls autoplay playsinline preload="auto" style="width:100%; margin-top:16px;"></audio>
                           </div>`
                    : `<div style="position:relative; z-index:1; width:100%; height:100%;">
                        <video id="player-video" controls playsinline preload="metadata" poster="${shiur.thumbnailDataUrl || shiur.thumbnailUrl || ''}" style="width:100%; height:100%;"></video>
                        <button id="videoPlayButton" class="btn btn-primary" style="position:absolute; left:50%; top:50%; transform:translate(-50%, -50%); display:none;">
                            <i class="fas fa-play"></i> Play
                        </button>
                    </div>`
                }
                </div>

                <div class="video-details" id="vDetails">
                    <h1 class="video-title">${shiur.title}</h1>

                    <div class="video-meta-row">
                        <span class="rabbi-badge" style="position:static; margin:0;">
                            <span class="rabbi-dot"></span>${formatRabbiName(shiur.rabbi)}
                        </span>
                        <span style="color:var(--text-muted); font-size:0.95rem;">${new Date(shiur.date).toLocaleDateString()}</span>
                        <span id="views-count" style="color:var(--text-muted); font-size:0.95rem; margin-left:auto; display:none;">
                            <i class="fas fa-eye"></i> <span id="views-num">0</span>
                        </span>
                        <button id="likeBtn" class="btn btn-secondary" style="margin-left:12px;">
                            <i class="far fa-thumbs-up"></i> <span id="likes-count" style="margin-left:6px;">0</span>
                        </button>
                    </div>

                    <div class="video-description">${shiur.description || 'No description provided.'}</div>

                    <div style="margin-top:24px; display:flex; flex-wrap:wrap; gap:8px;">
                        ${shiur.tags ? shiur.tags.map(t => `<span class="tag-badge">${t}</span>`).join('') : ''}
                    </div>

                    <div class="player-extra-controls" style="margin-top:30px; padding-top:20px; border-top:1px solid var(--border-light); display:flex; align-items:center; gap:12px;">
                        <span style="font-size:0.9rem; font-weight:600; color:var(--text-muted);">Playback Speed:</span>
                        <div class="speed-badge active" data-speed="1">1x</div>
                        <div class="speed-badge" data-speed="1.25">1.25x</div>
                        <div class="speed-badge" data-speed="1.5">1.5x</div>
                        <div class="speed-badge" data-speed="2">2x</div>
                    </div>
                </div>

                <div class="video-comments-area" id="vComments">
                    <h2 style="font-size:1.4rem; margin-bottom:24px; font-weight:700;">Comments</h2>

                    ${currentUser ? `
                    <div class="comment-composer">
                        <div style="display:flex; gap:16px;">
                            <img src="${currentUser.picture}" class="comment-avatar">
                            <div style="flex:1;">
                                <textarea id="commentInput" placeholder="Add a comment..." rows="2"></textarea>
                                <div style="text-align:right; margin-top:12px;">
                                    <button id="commentSubmitBtn" class="btn btn-primary">Post Comment</button>
                                </div>
                            </div>
                        </div>
                    </div>
                    ` : `
                    <div style="padding:30px; text-align:center; color:var(--text-muted); background:var(--bg-surface-hover); border-radius:var(--radius-lg); margin-bottom:30px;">
                        <p style="margin-bottom:12px;">Sign in to join the conversation.</p>
                        <button class="btn btn-primary js-google-sign-in">Sign In</button>
                    </div>
                    `}

                    <div id="commentsList">
                        <div class="skeleton" style="height:80px; margin-bottom:16px;"></div>
                        <div class="skeleton" style="height:80px; margin-bottom:16px;"></div>
                    </div>
                </div>
            </div>

            <aside class="related-column">
                <h3>Up Next</h3>
                <div id="relatedList" class="related-shiurim-container">
                    <div class="skeleton" style="height:100px;"></div>
                    <div class="skeleton" style="height:100px;"></div>
                    <div class="skeleton" style="height:100px;"></div>
                </div>
            </aside>
        </div>
    `;

            // --- Enhanced Video Player Logic ---
            const vid = document.getElementById('player-video');

            if (vid) {
                // 1. Attach error handler first
                vid.onerror = () => {
                    const error = vid.error;
                    console.error("Playback error details:", error);
                    let errorMsg = "Error loading audio/video source.";
                    if (error) {
                        if (error.code === 1) errorMsg = "Playback aborted.";
                        if (error.code === 2) errorMsg = "Network error.";
                        if (error.code === 3) errorMsg = "Decoding error.";
                        if (error.code === 4) errorMsg = "Resource not supported or found.";
                    }

                    showToast(errorMsg, "error");
                    document.getElementById('player-container').innerHTML = `
                        <div class="empty-state">
                            <i class="fas fa-exclamation-triangle" style="font-size:3rem; color:var(--color-danger); margin-bottom:16px;"></i>
                            <h3>Playback Error</h3>
                            <p>We couldn't load this shiur. Please try again later.</p>
                            <button class="btn btn-primary" onclick="window.location.reload()">Retry</button>
                        </div>
                    `;
                };

                // Load metadata first, then start playback when the browser has enough data.
                const playbackUrl = typeof shiur.playbackUrl === 'string' ? shiur.playbackUrl.trim() : '';
                if (!playbackUrl) {
                    showToast('This shiur has no playable media source.', 'error');
                    document.getElementById('player-container').innerHTML = `
                        <div class="empty-state">
                            <i class="fas fa-exclamation-triangle" style="font-size:3rem; color:var(--color-danger); margin-bottom:16px;"></i>
                            <h3>Playback Unavailable</h3>
                            <p>This shiur is missing a playable media source.</p>
                        </div>
                    `;
                    return;
                }
                vid.preload = 'metadata';
                vid.src = playbackUrl;
                vid.load();

                const playButton = document.getElementById('videoPlayButton');
                const tryPlay = () => {
                    vid.play().then(() => {
                        if (playButton) playButton.style.display = 'none';
                    }).catch(() => {
                        // Browsers may block autoplay after async navigation; expose an explicit control.
                        if (playButton) playButton.style.display = 'block';
                    });
                };
                vid.addEventListener('canplay', tryPlay, { once: true });
                if (playButton) playButton.onclick = tryPlay;
            }

            if (!vid) return;
            vid.onloadedmetadata = () => {
                localStorage.setItem(`vid_duration_${params.id}`, vid.duration);
                // Resume Playback
                const savedTime = localStorage.getItem(`vid_progress_${params.id}`);
                if (savedTime) vid.currentTime = parseFloat(savedTime);
            };

            vid.addEventListener('timeupdate', () => {
                localStorage.setItem(`vid_progress_${params.id}`, vid.currentTime);
            });

            // 1b. Playback Speed
            const speedBtns = document.querySelectorAll('.speed-badge');
            speedBtns.forEach(btn => {
                btn.onclick = () => {
                    speedBtns.forEach(b => b.classList.remove('active'));
                    btn.classList.add('active');
                    vid.playbackRate = parseFloat(btn.dataset.speed);
                };
            });

            // 2. Share
            document.getElementById('shareBtn').onclick = () => {
                const url = window.location.href;
                const shareModal = document.createElement('div');
                shareModal.className = 'share-modal-overlay';
                shareModal.innerHTML = `
                    <div class="share-modal">
                        <h3 style="margin-top:0;">Share Shiur</h3>
                        <p style="font-size:0.9rem; color:var(--text-muted);">Copy link to share this Torah.</p>
                        <input type="text" value="${url}" readonly style="margin-bottom:12px;">
                        <div style="display:flex; align-items:center; gap:8px; margin-bottom:20px;">
                            <input type="checkbox" id="shareAtTime" style="width:auto;">
                            <label for="shareAtTime" style="font-size:0.85rem;">Start at ${Math.floor(vid.currentTime)}s</label>
                        </div>
                        <div style="display:flex; justify-content:flex-end; gap:12px;">
                            <button class="btn btn-secondary" onclick="this.closest('.share-modal-overlay').remove()">Cancel</button>
                            <button class="btn btn-primary" id="copyShareLink">Copy Link</button>
                        </div>
                    </div>
                `;
                document.body.appendChild(shareModal);

                document.getElementById('copyShareLink').onclick = () => {
                    let finalUrl = url;
                    if (document.getElementById('shareAtTime').checked) {
                        const connector = finalUrl.includes('?') ? '&' : '?';
                        finalUrl += `${connector}t=${Math.floor(vid.currentTime)}`;
                    }
                    navigator.clipboard.writeText(finalUrl);
                    showToast('Link copied to clipboard');
                    shareModal.remove();
                };
            };

            // Check for timestamp in URL
            const urlParams = new URLSearchParams(window.location.search);
            const startTime = urlParams.get('t');
            if (startTime) vid.currentTime = parseFloat(startTime);

            // 3. Cinema Mode
            const cinemaBtn = document.getElementById('cinemaToggle');
            if (cinemaBtn) {
                cinemaBtn.onclick = () => {
                    document.body.classList.toggle('cinema-mode');
                    const isCinema = document.body.classList.contains('cinema-mode');
                    cinemaBtn.innerHTML = isCinema ? '<i class="fas fa-compress"></i>' : '<i class="fas fa-expand"></i>';
                };
            }

            // --- Background Data Loading (Non-blocking) ---

            // 4. Related & Up Next
            const loadRelated = async () => {
                const allData = await getAllShiurim();
                const related = allData
                    .filter(s => s.id !== params.id)
                    .sort((a, b) => (a.rabbi === shiur.rabbi ? -1 : 1) - (b.rabbi === shiur.rabbi ? -1 : 1))
                    .slice(0, 10);

                const rList = document.getElementById('relatedList');
                if (rList) {
                    rList.innerHTML = related.map(r => `
                    <a href="#" class="related-card" data-related-id="${r.id}">
                        <img data-src="${r.thumbnailDataUrl || r.thumbnailUrl}" class="related-thumb" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 9' fill='%23f3f4f6'%3E%3C/svg%3E">
                        <div class="related-info">
                            <h4>${r.title}</h4>
                            <span>${formatRabbiName(r.rabbi)}</span>
                        </div>
                    </a>
                `).join('');
                    rList.querySelectorAll('img[data-src]').forEach(img => imageObserver.observe(img));
                    rList.querySelectorAll('[data-related-id]').forEach(card => {
                        card.onclick = event => {
                            event.preventDefault();
                            const related = allData.find(item => item.id === card.dataset.relatedId);
                            if (related) loadPage('view_shiur', { id: related.id, preloadedShiur: related });
                        };
                    });
                }
            };
            loadRelated();

            // 5. Shortcuts
            const handleShortcuts = (e) => {
                if (e.target.tagName === 'TEXTAREA' || e.target.tagName === 'INPUT') return;
                switch (e.key.toLowerCase()) {
                    case ' ': case 'k': e.preventDefault(); vid.paused ? vid.play() : vid.pause(); break;
                    case 'arrowright': case 'l': vid.currentTime += 5; break;
                    case 'arrowleft': case 'j': vid.currentTime -= 5; break;
                    case 'f': if (document.fullscreenElement) document.exitFullscreen(); else vid.requestFullscreen(); break;
                }
            };
            document.addEventListener('keydown', handleShortcuts);

            // 6. Views
            const loadViews = async () => {
                const getViews = async () => workerFetch(VIDEO_API_URL, `/api/views/${encodeURIComponent(params.id)}`);
                const viewRes = await getViews();
                if (viewRes && viewRes.count !== undefined) {
                    const el = document.getElementById('views-count');
                    if (el) el.style.display = 'inline-block';
                    const numEl = document.getElementById('views-num');
                    if (numEl) numEl.textContent = viewRes.count;
                }
            };
            loadViews();

            vid.addEventListener('play', () => {
                const icon = document.getElementById('audioPlayIcon');
                if (icon) icon.className = 'fas fa-pause';

                workerFetch(VIDEO_API_URL, '/api/views/increment', {
                    method: 'POST',
                    body: JSON.stringify({ id: params.id }),
                    headers: { 'Content-Type': 'application/json' }
                });
            }, { once: true });

            vid.addEventListener('pause', () => {
                const icon = document.getElementById('audioPlayIcon');
                if (icon) icon.className = 'fas fa-headphones';
            });

            vid.addEventListener('playing', () => {
                const icon = document.getElementById('audioPlayIcon');
                if (icon) icon.className = 'fas fa-pause';
            });

            // 7. Likes
            const loadLikes = async () => {
                const getLikes = async () => workerFetch(VIDEO_API_URL, `/api/likes/${encodeURIComponent(params.id)}`);
                const toggleLike = async () => {
                    if (!currentUser) return showToast('Please sign in', 'error');
                    await workerFetch(VIDEO_API_URL, `/api/likes/${encodeURIComponent(params.id)}`, {
                        method: 'POST',
                        headers: { 'X-User-Email': currentUser.email }
                    });
                };

                const refreshLikes = async () => {
                    const likeData = await getLikes();
                    if (likeData) {
                        const btn = document.getElementById('likeBtn');
                        const cnt = document.getElementById('likes-count');
                        if (cnt) cnt.textContent = likeData.count;
                        if (btn) {
                            if (likeData.userLiked) {
                                btn.style.color = 'var(--color-accent)';
                                btn.querySelector('i').className = 'fas fa-thumbs-up';
                            } else {
                                btn.style.color = 'inherit';
                                btn.querySelector('i').className = 'far fa-thumbs-up';
                            }
                        }
                    }
                };

                const likeBtn = document.getElementById('likeBtn');
                if (likeBtn) {
                    likeBtn.onclick = async function () {
                        await toggleLike();
                        refreshLikes();
                    };
                }
                refreshLikes();
            };
            loadLikes();

            // 8. Comments
            const loadComments = async () => {
                const getComments = async () => workerFetch(VIDEO_API_URL, `/api/comments/${encodeURIComponent(params.id)}`);

                const refreshComments = async () => {
                    const res = await getComments();
                    const list = document.getElementById('commentsList');
                    if (!list) return;
                    list.innerHTML = '';

                    if (!res || !res.comments || res.comments.length === 0) {
                        list.innerHTML = `<p style="color:var(--text-muted); font-size:0.9rem;">No comments yet.</p>`;
                        return;
                    }

                    list.innerHTML = res.comments.map(c => `
                <div class="comment-item" style="padding:16px;">
                    <div class="comment-header" style="margin-bottom:8px;">
                        <div style="font-weight:700; font-size:0.9rem; color:var(--text-main);">${c.displayName || c.email}</div>
                        <div style="font-size:0.75rem; color:var(--text-muted);">${new Date(c.createdAt).toLocaleDateString()}</div>
                    </div>
                    <div class="comment-text" style="font-size:0.95rem;">${c.text}</div>
                    ${(currentUser && (currentUser.email === ADMIN_EMAIL || (ADMIN_EMAILS && ADMIN_EMAILS.includes(currentUser.email)))) ? `
                        <button onclick="deleteComment('${c.id}')" style="background:none; border:none; color:red; font-size:0.75rem; cursor:pointer; margin-top:8px;">Delete</button>
                    ` : ''}
                </div>
            `).join('');
                };

                if (currentUser) {
                    const submitBtn = document.getElementById('commentSubmitBtn');
                    if (submitBtn) {
                        submitBtn.onclick = async () => {
                            const inp = document.getElementById('commentInput');
                            const txt = inp.value.trim();
                            if (!txt) return;

                            await workerFetch(VIDEO_API_URL, `/api/comments/${encodeURIComponent(params.id)}`, {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json', 'X-User-Email': currentUser.email },
                                body: JSON.stringify({ text: txt })
                            });

                            inp.value = '';
                            refreshComments();
                        };
                    }
                }

                window.deleteComment = async (cid) => {
                    if (confirm('Delete comment?')) {
                        await workerFetch(VIDEO_API_URL, `/api/comments/${encodeURIComponent(params.id)}/${cid}`, {
                            method: 'DELETE',
                            headers: { 'X-User-Email': currentUser.email }
                        });
                        refreshComments();
                    }
                };

                refreshComments();
            };
            loadComments();
        },

        admin: async () => {
            if (!currentUser) return renderGoogleSignInPrompt('admin');
            if (!getStoredPassword()) return renderPasswordModal('admin');
            const [data, logs] = await Promise.all([
                fetchAdmin('/api/admin/shiurim'),
                fetchAdmin('/api/admin/upload-logs?limit=200')
            ]);

            // Build map of filename -> most recent uploader
            const uploaderMap = {};
            if (logs && logs.length) {
                for (const log of logs) {
                    if (log.filename && !uploaderMap[log.filename]) {
                        uploaderMap[log.filename] = log;
                    }
                }
            }

            contentArea.innerHTML = `
        <div class="flex-between" style="margin-bottom:24px; gap:12px; flex-wrap:wrap;">
            <h1>Admin Dashboard</h1>
            <div style="display:flex; gap:8px; flex-wrap:wrap;">
                <button class="btn btn-secondary" id="refreshThumbnailsBtn"><i class="fas fa-images"></i> Refresh All Thumbnails</button>
                <button class="btn btn-primary" onclick="loadPage('upload')">Upload New</button>
            </div>
        </div>
        <div id="thumbnailRefreshStatus" style="display:none; margin-bottom:20px; padding:12px 16px; border-radius:var(--radius-md); background:var(--bg-surface-hover); color:var(--text-muted);"></div>
        <div style="background:var(--bg-surface-solid); border:1px solid var(--border-light); border-radius:var(--radius-md); overflow:hidden;">
            ${data && data.length ? data.map(s => {
                const uploader = uploaderMap[s.id];
                const uploaderHtml = uploader
                    ? `<div style="font-size:0.75rem; color:var(--text-muted); margin-top:2px;">Uploaded by ${uploader.name} (${uploader.email}) on ${new Date(uploader.timestamp).toLocaleDateString()}</div>`
                    : '';
                return `
                <div style="padding:16px; border-bottom:1px solid var(--border-light); display:flex; justify-content:space-between; align-items:center;">
                    <div style="display:flex; gap:12px; align-items:center;">
                        <img src="${s.thumbnailDataUrl || s.thumbnailUrl || ''}" alt="Thumbnail for ${s.title}" style="width:60px; height:34px; object-fit:cover; border-radius:var(--radius-sm);" onerror="this.style.visibility='hidden';">
                        <div>
                            <div style="font-weight:600;">${s.title}</div>
                            <div style="font-size:0.8rem; color:var(--text-muted);">${formatRabbiName(s.rabbi)}</div>
                            ${uploaderHtml}
                        </div>
                    </div>
                    <button class="btn btn-secondary" style="padding:6px 12px; color:red; border-color:transparent;" data-del="${s.id}">Delete</button>
                </div>`;
            }).join('') : '<div style="padding:20px;">No shiurim.</div>'}
        </div>
    `;
            const refreshButton = document.getElementById('refreshThumbnailsBtn');
            const refreshStatus = document.getElementById('thumbnailRefreshStatus');
            if (refreshButton) refreshButton.onclick = async () => {
                const allVideos = (data || []).filter(video => {
                    const key = video.id || '';
                    return video.playbackUrl && !key.toLowerCase().startsWith('thumbnails/') && /\.(mp4|mov|m4v)$/i.test(key);
                });
                if (!confirm(`Regenerate first-frame thumbnails for ${allVideos.length} videos? Existing thumbnails will be overwritten.`)) return;
                refreshButton.disabled = true;
                refreshStatus.style.display = 'block';
                let completed = 0;
                let failed = 0;
                const videos = allVideos;
                const concurrency = 3;
                let nextIndex = 0;

                const processNext = async () => {
                    while (nextIndex < videos.length) {
                        const video = videos[nextIndex++];
                        refreshStatus.textContent = `Refreshing thumbnail ${completed + failed + 1} of ${videos.length}...`;
                        try {
                            const frame = await captureFirstFrame(video.playbackUrl);
                            const password = getStoredPassword();
                            const response = await fetch(`${MAIN_API_URL}/api/admin/refresh-thumbnails`, {
                                method: 'POST',
                                headers: {
                                    'Content-Type': 'application/json',
                                    'X-Upload-Password': password,
                                    'X-User-Email': currentUser.email,
                                    'X-User-Name': currentUser.name
                                },
                                body: JSON.stringify({ key: video.id, thumbnail: frame })
                            });
                            if (response.status === 401) {
                                sessionStorage.removeItem('uploadPassword');
                                renderPasswordModal('admin');
                                return;
                            }
                            const result = await response.json();
                            if (!response.ok || result.error) throw new Error(result.error || 'Upload failed');
                            completed++;
                        } catch (error) {
                            failed++;
                            console.error(`Thumbnail refresh failed for ${video.id}:`, error);
                        }
                        refreshStatus.textContent = `Refreshed ${completed + failed} of ${videos.length}...`;
                    }
                };

                await Promise.all(Array.from({ length: Math.min(concurrency, videos.length) }, processNext));
                refreshStatus.textContent = videos.length === 0
                    ? 'No supported video files were found.'
                    : `Finished: ${completed} refreshed${failed ? `, ${failed} skipped (unreadable or unavailable)` : ''}.`;
                refreshButton.disabled = false;
                sessionStorage.removeItem('allShiurim');
                allShiurimCache = [];
                await loadPage('admin');
            };

            contentArea.querySelectorAll('[data-del]').forEach(b => {
                b.onclick = async () => {
                    if (confirm('Delete?')) {
                        await fetchAdmin(`/api/admin/shiurim/${b.dataset.del}`, { method: 'DELETE' });
                        loadPage('admin');
                    }
                }
            });
        },

        upload: async () => {
            if (!currentUser) return renderGoogleSignInPrompt('upload');
            if (!getStoredPassword()) return renderPasswordModal('upload');

            // Get existing rabbis for the datalist
            const data = await getAllShiurim();
            const existingRabbis = [...new Set(data.map(s => s.rabbi).filter(r => r && r.toLowerCase() !== 'time4mishna'))];

            contentArea.innerHTML = `
        <div style="max-width:600px; margin:0 auto; background:var(--bg-surface-solid); padding:32px; border-radius:var(--radius-lg); border:1px solid var(--border-light);">
            <h2 style="margin-bottom:24px;">Upload Shiur</h2>
            <form id="upForm" style="display:grid; gap:16px;">
                <div>
                    <label>Speaker</label>
                    <input type="text" id="rabbi" list="rabbi-list" placeholder="e.g. Rabbi Hartman" required>
                    <datalist id="rabbi-list">
                        ${existingRabbis.map(r => `<option value="${r}">`).join('')}
                        <option value="guests">Guest Speakers</option>
                    </datalist>
                </div>
                <div><label>Title</label><input type="text" id="title" required></div>
                <div><label>Date</label><input type="date" id="date" required></div>
                <div><label>File</label><input type="file" id="fInput" accept="video/*,audio/*" required></div>
                <div id="prev" class="hidden"><video id="vidP" controls style="width:100%; border-radius:var(--radius-sm); margin-top:10px;"></video><button type="button" id="cap" class="btn btn-secondary" style="margin-top:8px;">Capture Thumb</button></div>
                <button type="submit" class="btn btn-primary" id="sBtn">Upload</button>
            </form>
        </div>
     `;
            const form = document.getElementById('upForm');
            const fInput = document.getElementById('fInput');
            const vidP = document.getElementById('vidP');

            fInput.onchange = (e) => {
                if (e.target.files[0]) {
                    vidP.src = URL.createObjectURL(e.target.files[0]);
                    document.getElementById('prev').classList.remove('hidden');
                }
            };

            document.getElementById('cap').onclick = () => {
                const c = document.createElement('canvas');
                c.width = vidP.videoWidth; c.height = vidP.videoHeight;
                c.getContext('2d').drawImage(vidP, 0, 0);
                capturedThumbnailDataUrl = c.toDataURL('image/jpeg', 0.8);
                alert('Thumbnail Captured');
            };

            form.onsubmit = async (e) => {
                e.preventDefault();
                const btn = document.getElementById('sBtn');
                btn.disabled = true; btn.textContent = 'Uploading...';

                try {
                    const file = fInput.files[0];
                    if (!capturedThumbnailDataUrl) throw new Error('Capture thumbnail first');

                    const password = getStoredPassword();
                    const authHeaders = {
                        'X-Upload-Password': password,
                        'X-User-Email': currentUser.email,
                        'X-User-Name': currentUser.name
                    };

                    // Step 1: Prepare upload (starts multipart upload on worker)
                    const prep = await fetch(`${MAIN_API_URL}/api/admin/prepare-upload`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json', ...authHeaders },
                        body: JSON.stringify({
                            title: document.getElementById('title').value,
                            rabbi: document.getElementById('rabbi').value,
                            date: document.getElementById('date').value,
                            fileName: file.name
                        })
                    });
                    if (prep.status === 401) {
                        sessionStorage.removeItem('uploadPassword');
                        renderPasswordModal('upload');
                        return;
                    }
                    const { r2Key, uploadId, thumbnailUrl } = await prep.json();

                    // Step 2: Upload video parts concurrently (10MB each, up to 4 at a time).
                    const uploadedParts = await uploadMultipartParts({
                        file,
                        r2Key,
                        uploadId,
                        headers: authHeaders,
                        onProgress: (completed, total) => {
                            btn.textContent = `Uploaded ${completed}/${total} parts...`;
                        }
                    });

                    // Step 3: Complete the multipart upload
                    btn.textContent = 'Finalizing...';
                    const completeRes = await fetch(`${MAIN_API_URL}/api/admin/complete-upload`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json', ...authHeaders },
                        body: JSON.stringify({ r2Key, uploadId, parts: uploadedParts })
                    });
                    const completeData = await completeRes.json();
                    if (completeData.error) throw new Error(completeData.error);

                    // Step 4: Upload thumbnail (small file, simple proxy)
                    if (thumbnailUrl && capturedThumbnailDataUrl) {
                        btn.textContent = 'Uploading thumbnail...';
                        const thumbBlob = await (await fetch(capturedThumbnailDataUrl)).blob();
                        await fetch(thumbnailUrl, {
                            method: 'PUT',
                            headers: { 'Content-Type': 'image/jpeg', ...authHeaders },
                            body: thumbBlob
                        });
                    }

                    // Clear cache
                    sessionStorage.removeItem('allShiurim');
                    allShiurimCache = [];

                    alert('Uploaded successfully to R2!');
                    loadPage('home');
                } catch (err) { alert(err.message); btn.disabled = false; btn.textContent = 'Upload Shiur'; }
            };

        },

        upload_time4mishna: () => {
            if (!currentUser) return renderGoogleSignInPrompt('upload_time4mishna');
            if (!getStoredPassword()) return renderPasswordModal('upload_time4mishna');
            contentArea.innerHTML = `
        <div style="max-width:600px; margin:0 auto; background:var(--bg-surface-solid); padding:32px; border-radius:var(--radius-lg); border:1px solid var(--border-light);">
            <div class="flex-between" style="margin-bottom:24px;">
                <h2 style="margin:0;">Upload to Time4Mishna (Audio)</h2>
                <button class="btn btn-secondary" onclick="loadPage('time4mishna')">Cancel</button>
            </div>
            <form id="upForm" style="display:grid; gap:16px;">
                <div style="display:none;"><input type="text" id="rabbi" value="time4mishna"></div>
                <div><label>Title</label><input type="text" id="title" required></div>
                <div><label>Date</label><input type="date" id="date" required></div>
                <div><label>Audio File</label><input type="file" id="fInput" accept="audio/*" required></div>
                <button type="submit" class="btn btn-primary" id="sBtn" style="margin-top:16px;">Upload Audio</button>
            </form>
        </div>
     `;
            const form = document.getElementById('upForm');
            const fInput = document.getElementById('fInput');

            form.onsubmit = async (e) => {
                e.preventDefault();
                const btn = document.getElementById('sBtn');
                btn.disabled = true; btn.textContent = 'Uploading...';

                try {
                    const file = fInput.files[0];
                    if (!file) throw new Error('No file selected');

                    const password = getStoredPassword();
                    const authHeaders = {
                        'X-Upload-Password': password,
                        'X-User-Email': currentUser.email,
                        'X-User-Name': currentUser.name
                    };

                    const prep = await fetch(`${MAIN_API_URL}/api/admin/prepare-upload`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json', ...authHeaders },
                        body: JSON.stringify({
                            title: document.getElementById('title').value,
                            rabbi: 'time4mishna',
                            date: document.getElementById('date').value,
                            fileName: file.name
                        })
                    });
                    if (prep.status === 401) {
                        sessionStorage.removeItem('uploadPassword');
                        renderPasswordModal('upload_time4mishna');
                        return;
                    }
                    const { r2Key, uploadId } = await prep.json();

                    // Upload audio parts concurrently (10MB each, up to 4 at a time).
                    const uploadedParts = await uploadMultipartParts({
                        file,
                        r2Key,
                        uploadId,
                        headers: authHeaders,
                        onProgress: (completed, total) => {
                            btn.textContent = `Uploaded ${completed}/${total} parts...`;
                        }
                    });

                    btn.textContent = 'Finalizing...';
                    const completeRes = await fetch(`${MAIN_API_URL}/api/admin/complete-upload`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json', ...authHeaders },
                        body: JSON.stringify({ r2Key, uploadId, parts: uploadedParts })
                    });
                    const completeData = await completeRes.json();
                    if (completeData.error) throw new Error(completeData.error);

                    // Clear cache
                    sessionStorage.removeItem('allShiurim');
                    allShiurimCache = [];

                    alert('Uploaded to R2!');
                    loadPage('time4mishna');
                } catch (err) { alert(err.message); btn.disabled = false; btn.textContent = 'Upload Audio'; }
            };
        },
    };

    function renderGoogleSignInPrompt(target) {
        contentArea.innerHTML = `
    <div style="max-width:400px; margin:60px auto; background:var(--bg-surface-solid); padding:30px; border-radius:var(--radius-md); border:1px solid var(--border-light); text-align:center;">
        <h3>Sign In Required</h3>
        <p style="color:var(--text-muted); margin:12px 0 20px;">Please sign in with Google to access admin features.</p>
        <div id="googleSignInModal" style="display:flex; justify-content:center;"></div>
    </div>
`;
        if (window.google && window.google.accounts && window.google.accounts.id) {
            window.google.accounts.id.initialize({
                client_id: GOOGLE_CLIENT_ID,
                callback: (response) => {
                    window.handleCredentialResponse(response);
                    setTimeout(() => {
                        if (currentUser) renderPasswordModal(target);
                    }, 500);
                },
                auto_select: false
            });
            window.google.accounts.id.renderButton(
                document.getElementById('googleSignInModal'),
                { type: 'standard', theme: 'outline', size: 'large', text: 'signin_with' }
            );
        } else {
            document.getElementById('googleSignInModal').innerHTML = '<button class="btn btn-primary js-google-sign-in">Sign In with Google</button>';
        }
    }

    function renderPasswordModal(target) {
        if (!currentUser) return renderGoogleSignInPrompt(target);

        contentArea.innerHTML = `
    <div style="max-width:400px; margin:60px auto; background:var(--bg-surface-solid); padding:30px; border-radius:var(--radius-md); border:1px solid var(--border-light); text-align:center;">
        <h3>Admin Access</h3>
        <p style="color:var(--text-muted); margin:12px 0;">Signed in as ${currentUser.name}</p>
        <input type="password" id="pwd" placeholder="Admin Password" style="margin:16px 0;">
        <button id="pwdBtn" class="btn btn-primary">Unlock</button>
    </div>
`;
        document.getElementById('pwdBtn').onclick = async () => {
            const password = document.getElementById('pwd').value;
            if (!password) return alert('Please enter a password');
            try {
                const res = await fetch(`${MAIN_API_URL}/api/admin/shiurim`, {
                    headers: {
                        'X-Upload-Password': password,
                        'X-User-Email': currentUser.email,
                        'X-User-Name': currentUser.name
                    }
                });
                if (res.ok) {
                    setStoredPassword(password);
                    loadPage(target);
                } else {
                    alert('Incorrect password');
                }
            } catch (err) {
                alert('Failed to verify password');
            }
        };
    }

    // --- Routing & Transitions ---
    window.loadPage = (p, params, skipHistory = false) => {
        document.body.classList.remove('cinema-mode');
        navItems.forEach(n => {
            n.classList.remove('active');
            if (n.dataset.page === p) n.classList.add('active');
        });

        const render = async () => {
            document.body.setAttribute('data-page-context', p);
            window.scrollTo(0, 0);
            if (pages[p]) await pages[p](params || {});
            else await pages.home();
        };

        // View Transition API can interfere with video initialization in some browsers
        if (document.startViewTransition && p !== 'view_shiur') {
            document.startViewTransition(() => render());
        } else {
            render();
        }

        if (!skipHistory) {
            const hash = `${p}${params && params.id ? '/' + params.id : ''}`;
            const url = `#${hash}`;
            if (window.location.hash !== url) {
                window.history.pushState({ p, params }, null, url);
            }
        }
    };

    window.onpopstate = (e) => {
        if (e.state) {
            loadPage(e.state.p, e.state.params, true);
        } else {
            const initialHash = window.location.hash.slice(1);
            const [page, param] = initialHash.split('/');
            loadPage(page || 'home', param ? { id: param } : {}, true);
        }
    };

    // --- Events & Init ---
    const toggleTheme = () => applyTheme(document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark');
    if (themeToggle) themeToggle.addEventListener('click', toggleTheme);
    if (mobileThemeToggle) mobileThemeToggle.addEventListener('click', toggleTheme);

    document.addEventListener('click', (e) => {
        const link = e.target.closest('[data-page]');
        if (link && !e.target.closest('.nav-item') && !e.target.closest('.bottom-nav-item')) {
            e.preventDefault();
            loadPage(link.dataset.page);
        }

        const navItem = e.target.closest('.nav-item, .bottom-nav-item');
        if (navItem && navItem.dataset.page) {
            e.preventDefault();
            loadPage(navItem.dataset.page);
        }

        const card = e.target.closest('.video-card');
        if (card && card.dataset.shiurId) {
            e.preventDefault();
            loadPage('view_shiur', { id: card.dataset.shiurId });
        }
    });

    // Initialize Google Identity Services after the async script is available.
    initializeGoogleSignIn();
    document.querySelectorAll('.js-google-sign-in').forEach(button => {
        button.addEventListener('click', startGoogleSignIn);
    });
    // Dynamic page content (comments and other sign-in prompts) is handled here.
    contentArea.addEventListener('click', event => {
        if (event.target.closest('.js-google-sign-in')) startGoogleSignIn();
    });
    window.addEventListener('google-signin-error', event => showToast(event.detail || 'Unable to sign in with Google', 'error'));

    // Profile Dropdown Logic
    const pToggle = document.getElementById('profileToggle'); // Desktop
    const mProfile = document.getElementById('mobileProfileToggle'); // Mobile Header
    const globalMenu = document.getElementById('globalMenu');

    const toggleMenu = (e) => {
        e.stopPropagation();
        e.preventDefault();
        globalMenu.classList.toggle('active');
    };

    if (pToggle) pToggle.onclick = toggleMenu;
    if (mProfile) mProfile.onclick = toggleMenu;

    document.addEventListener('click', (e) => {
        if (!globalMenu.contains(e.target) && (!mProfile || !mProfile.contains(e.target)) && (!pToggle || !pToggle.contains(e.target))) {
            globalMenu.classList.remove('active');
        }
    });

    document.getElementById('signOutBtn').onclick = () => {
        localStorage.removeItem('googleUser');
        currentUser = null;
        if (window.google?.accounts?.id) window.google.accounts.id.disableAutoSelect();
        window.location.reload();
    };

    // Auth UI Update
    window.addEventListener('google-signin-success', (e) => {
        currentUser = e.detail;

        const desktopAuth = document.getElementById('desktop-auth-container');
        if (desktopAuth) desktopAuth.style.display = 'none';
        document.getElementById('profileDropdown').style.display = 'block';
        document.getElementById('userAvatar').src = currentUser.picture;

        const mobileAuth = document.getElementById('mobile-auth-container');
        if (mobileAuth) mobileAuth.style.display = 'none';
        const mobileProfile = document.getElementById('mobileProfileDropdown');
        if (mobileProfile) mobileProfile.style.display = 'block';
        const mobileAvatar = document.getElementById('mobileUserAvatar');
        if (mobileAvatar) mobileAvatar.src = currentUser.picture;

        document.getElementById('menuLoggedOut').style.display = 'none';
        document.getElementById('menuLoggedIn').style.display = 'block';
        document.getElementById('menuUserName').textContent = currentUser.name;

        if (ADMIN_EMAILS && ADMIN_EMAILS.includes(currentUser.email)) {
            document.getElementById('adminLink').style.display = 'flex';
            document.getElementById('uploadLink').style.display = 'flex';
        }
    });

    // Boot
    const storedUser = localStorage.getItem('googleUser');
    if (storedUser) {
        try {
            window.dispatchEvent(new CustomEvent('google-signin-success', { detail: JSON.parse(storedUser) }));
        } catch {
            localStorage.removeItem('googleUser');
        }
    }

    applyTheme(localStorage.getItem('theme') || 'light');

    const initialHash = window.location.hash.slice(1);
    const [page, param] = initialHash.split('/');
    loadPage(page || 'home', param ? { id: param } : {});

    // Check for new community posts
    checkLatestPost();
});
