<template>
  <div class="commit-graph-page">
    <!-- Header -->
    <div class="graph-header">
      <div class="d-flex align-items-center gap-3">
        <router-link :to="{ name: 'RepositoryDetail', params: { id: repoId } }" class="btn btn-outline-secondary">
          <i class="bi bi-arrow-left"></i> Назад
        </router-link>
        <h2 class="mb-0">История коммитов</h2>
      </div>
      
      <div class="graph-controls">
        <select v-model="currentBranch" class="form-select form-select-sm" style="width: 200px;">
          <option v-for="branch in branches" :key="branch" :value="branch">
            {{ branch === 'all' ? 'Все ветки' : branch }}
          </option>
        </select>
        
        <div class="btn-group btn-group-sm">
          <button class="btn btn-outline-secondary" @click="resetSimulation" title="Перезапустить симуляцию (R)">
            ⟲
          </button>
          <button class="btn btn-outline-secondary" @click="centerGraph" title="Центрировать (C)">
            ⊕
          </button>
        </div>

        <select v-model="selectedMetric" class="form-select form-select-sm" style="width: 180px;">
          <option value="importance">Важность</option>
          <option value="degree">Связность</option>
          <option value="betweenness">Влияние</option>
          <option value="pagerank">Авторитет</option>
        </select>
      </div>
    </div>

    <!-- Error Alert -->
    <div v-if="debugError" class="alert alert-danger py-2 mb-3">
      <strong>Ошибка D3:</strong> {{ debugError }}
    </div>

    <!-- Loading -->
    <div v-if="loading" class="loading-container">
      <div class="spinner-border text-primary" role="status">
        <span class="visually-hidden">Загрузка...</span>
      </div>
    </div>

    <!-- D3 Graph Container -->
    <div v-else class="graph-container" ref="graphContainer">
      <svg ref="svgElement" class="commit-graph-svg"></svg>
      
      <!-- Tooltip -->
      <div 
        v-if="tooltipData" 
        class="commit-tooltip"
        :style="{ left: tooltipPosition.x + 'px', top: tooltipPosition.y + 'px' }"
      >
        <div class="tooltip-header">
          <span class="tooltip-hash">{{ tooltipData.shortHash }}</span>
          <span class="tooltip-branch" :style="{ background: tooltipData.branchColor }">{{ tooltipData.branch }}</span>
        </div>
        <div class="tooltip-message">{{ tooltipData.message }}</div>
        <div class="tooltip-metrics">
          <div class="metric-label">Связность:</div><div class="metric-value">{{ formatMetric(tooltipData.metrics?.degree) }}</div>
          <div class="metric-label">Авторитет:</div><div class="metric-value">{{ formatMetric(tooltipData.metrics?.pagerank) }}</div>
          <div class="metric-label">Влияние:</div><div class="metric-value">{{ formatMetric(tooltipData.metrics?.betweenness) }}</div>
        </div>
        <div class="tooltip-meta">
          <div class="tooltip-author" :style="{ color: tooltipData.branchColor }">{{ tooltipData.author }}</div>
          <div class="tooltip-date">{{ formatDate(tooltipData.date) }}</div>
        </div>
      </div>
    </div>

    <!-- Stats Overlay -->
    <div class="graph-legend">
        <span class="badge bg-secondary me-2">Commits: {{ commits.length }}</span>
        <div class="legend-items d-inline-flex">
           <div class="legend-item me-3"><span class="legend-dot" style="background: #3b82f6;"></span> Main</div>
           <div class="legend-item"><span class="legend-dot" style="background: #fbbf24;"></span> Release</div>
        </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import * as d3 from 'd3';
import { apiClient } from '@/js/api/manager';
import { versionManagementEndpoints } from '../js/endpoints';
import { calculateAllMetrics } from '../js/graphUtils';

const route = useRoute();
const router = useRouter();
const repoId = route.params.id;

// Refs
const graphContainer = ref(null);
const svgElement = ref(null);
const loading = ref(true);
const commits = ref([]);
const branches = ref(['all']);
const currentBranch = ref('all');
const selectedMetric = ref('importance');
const debugError = ref('');

// Tooltip
const tooltipData = ref(null);
const tooltipPosition = ref({ x: 0, y: 0 });

// D3 elements
let svg = null;
let simulation = null;
let nodesGroup = null;
let linksGroup = null;
let zoom = null;

// Constants
const LANE_WIDTH = 120;
const Y_SPACING = 70;

// Branch colors
const specialBranches = {
  'main': { color: '#3b82f6', type: 'main' },
  'master': { color: '#3b82f6', type: 'main' },
  'dev': { color: '#10b981', type: 'main' },
  'develop': { color: '#10b981', type: 'main' },
  // Explicit colors for demo branches
  'feature-auth': { color: '#eab308', type: 'user' }, // Yellow
  'feature-ui': { color: '#ec4899', type: 'user' },   // Pink
  'feature-api': { color: '#8b5cf6', type: 'user' },  // Purple
};
const releaseBranch = { color: '#fbbf24', type: 'release' };
const userBranchColors = ['#f9a8d4', '#a5b4fc', '#86efac', '#fcd34d', '#c4b5fd', '#67e8f9'];

const getBranchInfo = (branchName) => {
  if (!branchName) return { color: '#9ca3af', type: 'user' };
  const name = branchName.toLowerCase();
  if (specialBranches[name]) return specialBranches[name];
  if (name.includes('release') || name.startsWith('v')) return releaseBranch;
  let hash = 0;
  for (let i = 0; i < name.length; i++) hash = name.charCodeAt(i) + ((hash << 5) - hash);
  return { color: userBranchColors[Math.abs(hash) % userBranchColors.length], type: 'user' };
};

const getNodeRadius = (d) => {
  const metricValue = d.metrics?.[selectedMetric.value] || 0;
  // Reduced size: base 6px, max +6px (total 12px)
  return 6 + metricValue * 6;
};

// ... DATA GENERATOR ...
// ... DATA GENERATOR ...
// ... DATA GENERATOR ...
// ... DATA GENERATOR ...
const getDemoCommits = () => {
    const commits = [];
    const now = Date.now();
    const genHash = (id) => {
        const uniquePart = id.toString(16).padStart(8, '0'); 
        const randomPart = Array(32).fill(0).map((_, i) => ((id + i) % 16).toString(16)).join('');
        return uniquePart + randomPart;
    };
    let currentId = 0xabcdef;
    
    // Helper
    const addCommit = (branch, parents, lane, time, msg, author) => {
        const hash = genHash(currentId++);
        const parentHashes = parents ? (Array.isArray(parents) ? parents.map(p => p.hash) : [parents.hash]) : [];
        
        const commit = {
            hash, message: msg, author, id: hash,
            date: new Date(time).toISOString(), branch, lane,
            parents: parentHashes,
            filesChanged: Math.floor(Math.random() * 5) + 1
        };
        commits.push(commit);
        return commit;
    };

    // --- SCENARIO: Diamond Merge Workflow ---
    // A -- B -- C -- D -- E   (Ivan on dev)
    //            \
    //             F -- G      (Petr on parallel)
    //                   \
    //                    M    (Merge)

    let t = now - 100000000;
    const hour = 3600000;

    // 1. Common History (A, B, C) on 'dev'
    const A = addCommit('dev', null, 0, t, 'A: Init project', 'Ivan');
    const B = addCommit('dev', A,    0, t + hour, 'B: Setup libs', 'Ivan');
    const C = addCommit('dev', B,    0, t + 2*hour, 'C: Core logic', 'Ivan');

    // 2. Ivan continues on 'dev' (D, E)
    // Pushed first, so it stays on main line (Lane 0)
    const D = addCommit('dev', C, 0, t + 3*hour, 'D: feat: Add function 1', 'Ivan');
    const E = addCommit('dev', D, 0, t + 4*hour, 'E: chore: Update libs', 'Ivan');

    // 3. Petr works in parallel (F, G)
    // Diverged from C. Branch 'dev-petr' (Lane 1) - simulates Petr's local dev copy
    const F = addCommit('dev-petr', C, 1, t + 3.5*hour, 'F: docs: Update docs', 'Petr');
    const G = addCommit('dev-petr', F, 1, t + 4.5*hour, 'G: feat: Add function 2', 'Petr');

    // 4. Merge (M)
    // Merges Petr's work (G) into Ivan's work (E)
    // Result is on 'dev' (Lane 0)
    const M = addCommit('dev', [E, G], 0, t + 6*hour, "M: Merge branch 'feature-petr'", 'Petr');

    return commits.sort((a,b) => new Date(b.date) - new Date(a.date));
};
// ... END DATA GENERATOR ...


// Filter commits based on selected branch
const filteredCommits = computed(() => {
    const target = currentBranch.value;
    
    // Overview (Default)
    if (!target || target === 'all') return commits.value;
    
    // Strict Main View
    if (target === 'main') return commits.value.filter(c => c.branch === 'main');
    
    // Smart Dev View (Show Dev + Petr's work)
    if (target === 'dev') {
        return commits.value.filter(c => c.branch === 'dev' || c.branch === 'dev-petr');
    }
    
    // Fallback for any other specific branch
    return commits.value.filter(c => c.branch === target);
});

const loadCommits = async () => {
    loading.value = true;
    commits.value = [];
    debugError.value = '';
    
    try {
        console.log('Loading commits...');
        const response = await apiClient.get(versionManagementEndpoints.repositories.commitsList(repoId));
        let data = [];
        if (response.success && response.data) {
             data = Array.isArray(response.data) ? response.data : (response.data.results || []);
        }
        
        if (data.length === 0) {
            console.log('No real commits, loading demo...');
            data = getDemoCommits();
        }
        
        // Prepare nodes
        commits.value = data.map(c => ({
             ...c,
             id: c.hash || c.id, 
             shortHash: (c.hash||'').substring(0,7),
             branchColor: getBranchInfo(c.branch).color,
             branchType: getBranchInfo(c.branch).type
        }));
        
        // Update branches list for dropdown
        const uniqueBranches = new Set(commits.value.map(c => c.branch));
        // Filter out helper branches (like dev-petr) from the UI dropdown
        const distinctBranches = Array.from(uniqueBranches).filter(b => !b.includes('petr'));
        branches.value = ['all', ...distinctBranches];
        if (!currentBranch.value) currentBranch.value = 'all';
        
        console.log('Commits loaded:', commits.value.length);
        
        await nextTick();
        initD3Graph();
        
    } catch (e) {
        console.error('Error loading:', e);
        debugError.value = 'Data Load Error: ' + e.message;
        // Fallback
        commits.value = getDemoCommits().map(c => ({
             ...c, id: c.hash, shortHash: c.hash.substring(0,7),
             branchColor: getBranchInfo(c.branch).color,
             branchType: getBranchInfo(c.branch).type
        }));
    } finally {
        // Critical: Set loading to false so v-else renders the container
        loading.value = false;
        // Wait for Vue to update DOM
        await nextTick();
        // Give a small buffer for heavy rendering
        setTimeout(initD3Graph, 50);
    }
};

const initD3Graph = () => {
    if (!filteredCommits.value.length) return;
    
    // Safety check with retry
    if (!svgElement.value || !graphContainer.value) {
        console.warn('DOM not ready, retrying...');
        setTimeout(initD3Graph, 100);
        return;
    }
    
    // reset error if we got here
    debugError.value = '';

    try {
        const width = graphContainer.value.clientWidth || 800;
        const height = graphContainer.value.clientHeight || 800;
        
        d3.select(svgElement.value).selectAll('*').remove();
        svg = d3.select(svgElement.value).attr('width', width).attr('height', height);
        
        const g = svg.append('g');
        zoom = d3.zoom().scaleExtent([0.1, 4]).on('zoom', e => g.attr('transform', e.transform));
        svg.call(zoom);
        
        const nodes = JSON.parse(JSON.stringify(filteredCommits.value));
        // Calculate initial positions
        nodes.forEach((n, i) => {
            n.x = (n.lane || 0) * LANE_WIDTH + 150;
            n.y = i * Y_SPACING + 100;
        });
        
        const links = [];
        const nodeMap = new Map(nodes.map(n => [n.id, n]));
        nodes.forEach(n => {
            if(n.parents) n.parents.forEach(p => {
                if(nodeMap.has(p)) links.push({ source: n.id, target: p, color: n.branchColor });
            });
        });
        
        calculateAllMetrics(nodes, links);
        console.log('Metrics calculated. Sample node metrics:', nodes[0]?.metrics, 'Total nodes:', nodes.length);
        
        // --- STATIC LAYOUT (No Force Simulation) ---
        // 1. Assign fixed coordinates
        nodes.forEach((d, i) => {
            d.x = 100 + (d.lane || 0) * LANE_WIDTH;
            d.y = 80 + i * Y_SPACING;
        });

        // 2. Resolve link references manually since we don't have forceLink doing it
        const resolvedLinks = links.map(l => {
            const sourceNode = nodeMap.get(l.source);
            const targetNode = nodeMap.get(l.target);
            if (!sourceNode || !targetNode) return null;
            return {
                ...l,
                source: sourceNode,
                target: targetNode
            };
        }).filter(l => l !== null);

        // 3. Render Links (Static)
        linksGroup = g.append('g').selectAll('path')
            .data(resolvedLinks).enter().append('path')
            .attr('d', d => {
                 const sx = d.source.x;
                 const sy = d.source.y;
                 const tx = d.target.x;
                 const ty = d.target.y;
                 // S-curve for vertical layout
                 return `M ${sx} ${sy} C ${sx} ${sy + Y_SPACING/2}, ${tx} ${ty - Y_SPACING/2}, ${tx} ${ty}`;
            })
            .attr('stroke', d => d.color)
            .attr('stroke-width', 2)
            .attr('fill', 'none')
            .attr('opacity', 0.6);
            
        // 4. Render Nodes (Static - No Drag)
        nodesGroup = g.append('g').selectAll('g')
            .data(nodes).enter().append('g')
            .attr('transform', d => `translate(${d.x}, ${d.y})`) 
            .attr('class', 'node-group')
            .on('mouseover', function(e, d) {
                // Target the shape (circle or polygon)
                d3.select(this).select('.node-shape').classed('node-hovered', true);
                showTooltip(d, e);
            })
            .on('mouseout', function() {
                d3.select(this).select('.node-shape').classed('node-hovered', false);
                hideTooltip();
            })
            .on('click', (event, d) => router.push({ name: 'CommitDetail', params: { id: repoId, hash: d.hash } }));
            
        // Use 'each' to handle different shapes based on data
        nodesGroup.each(function(d) {
            const el = d3.select(this);
            const r = getNodeRadius(d);
            const isMerge = d.parents && d.parents.length > 1;
            
            if (isMerge) {
                // Render Octagon (Solid filled - same color as branch)
                const points = [];
                for(let i = 0; i < 8; i++) {
                    const angle = (i * 45 + 22.5) * (Math.PI / 180); 
                    points.push([r * Math.cos(angle), r * Math.sin(angle)]);
                }
                el.append('polygon')
                    .attr('points', points.map(p => p.join(',')).join(' '))
                    .attr('fill', d.branchColor) // Solid fill with branch color
                    .attr('stroke', 'none')
                    .attr('class', 'node-shape');
            } else {
                // Render Circle (Filled, no white stroke)
                el.append('circle')
                    .attr('r', r)
                    .attr('fill', d.branchColor)
                    .attr('stroke', 'none') // No white border
                    .attr('class', 'node-shape');
            }
        });
            
        nodesGroup.append('text')
            .text(d => d.shortHash)
            .attr('dx', 18)
            .attr('dy', 4)
            .attr('fill', '#999')
            .style('font-family', 'monospace')
            .style('font-size', '11px');
            
        // No simulation.on('tick') needed!
        
        // Center View
        const initialTransform = d3.zoomIdentity.translate(50, 50).scale(1);
        svg.call(zoom.transform, initialTransform);
        
    } catch (e) {
        console.error('D3 Init Error:', e);
        debugError.value = 'D3 Error: ' + e.message;
    }
};

// Drag & Zoom helpers
const dragStart = (e, d) => { if(!e.active) simulation.alphaTarget(0.3).restart(); d.fx = d.x; d.fy = d.y; };
const dragging = (e, d) => { d.fx = e.x; d.fy = e.y; };
const dragEnd = (e, d) => { if(!e.active) simulation.alphaTarget(0); d.fx = null; d.fy = null; };
const resetSimulation = () => simulation && simulation.alpha(1).restart();
const centerGraph = () => svg && svg.transition().duration(750).call(zoom.transform, d3.zoomIdentity.translate(width/2 - 200, 50).scale(1.2));
const showTooltip = (d, e) => { tooltipData.value = d; tooltipPosition.value = { x: e.clientX+15, y: e.clientY-10 }; };
const hideTooltip = () => tooltipData.value = null;
const formatMetric = v => v ? (v*100).toFixed(1)+'%' : '-';
const formatDate = d => new Date(d).toLocaleDateString();

const updateNodeVisuals = () => {
    if (!svg) return;
    
    // Update circles (normal commits)
    svg.selectAll('.node-group circle.node-shape')
       .transition().duration(500)
       .attr('r', d => getNodeRadius(d));
    
    // Update polygons (merge commits) - recalculate points
    svg.selectAll('.node-group polygon.node-shape')
       .transition().duration(500)
       .attr('points', d => {
           const r = getNodeRadius(d);
           const pts = [];
           for(let i = 0; i < 8; i++) {
               const angle = (i * 45 + 22.5) * (Math.PI / 180); 
               pts.push([r * Math.cos(angle), r * Math.sin(angle)]);
           }
           return pts.map(p => p.join(',')).join(' ');
       });
};

watch(selectedMetric, () => {
    updateNodeVisuals(); // Smooth transition for metric changes
});

watch(currentBranch, () => {
    initD3Graph(); // Re-build graph when branch changes
});

onMounted(() => {
    loadCommits();
    window.addEventListener('resize', () => initD3Graph());
});
onUnmounted(() => window.removeEventListener('resize', () => initD3Graph()));
</script>

<style scoped>
/* Full screen layout */
.commit-graph-page { 
    position: relative; /* Back to normal flow to respect sidebar */
    width: 100%;
    height: 90vh; /* Fill most of the screen */
    max-height: 100vh;
    padding: 0; 
    display: flex; 
    flex-direction: column; 
    overflow: hidden; /* Prevent scrolling */
    background-color: #18181a; /* New requested color */
    border-radius: 8px; /* Slight radius for aesthetic */
}

.graph-header { 
    display: flex; 
    justify-content: space-between; 
    align-items: center; 
    padding: 15px 20px; 
    background-color: #18181a; /* Match background */
    border-bottom: 1px solid rgba(255,255,255,0.05); /* Softer border */
    z-index: 10;
}

.graph-controls { display: flex; gap: 10px; }

.graph-container { 
    flex: 1; 
    width: 100%;
    background: transparent; 
    position: relative; 
    overflow: hidden;
}

/* Tooltip & Legend */
.commit-tooltip { position: fixed; background: #222; padding: 12px; border-radius: 8px; z-index: 9999; color: #fff; pointer-events: none; border: 1px solid #444; min-width: 180px; }
.tooltip-header { display: flex; gap: 8px; align-items: center; margin-bottom: 6px; }
.tooltip-hash { font-family: monospace; font-size: 0.85rem; }
.tooltip-branch { padding: 2px 6px; border-radius: 4px; font-size: 0.75rem; color: #fff; }
.tooltip-message { font-size: 0.9rem; margin-bottom: 8px; color: #ddd; }
.tooltip-metrics { display: grid; grid-template-columns: auto auto; gap: 2px 12px; font-size: 0.8rem; margin-bottom: 8px; }
.metric-label { color: #888; }
.metric-value { color: #fff; }
.tooltip-meta { border-top: 1px solid #444; padding-top: 8px; margin-top: 4px; }
.tooltip-author { font-weight: 500; margin-bottom: 2px; }
.tooltip-date { font-size: 0.8rem; color: #888; }
.metric-row { display: flex; justify-content: space-between; font-size: 0.8rem; width: 200px; }

/* NODE ANIMATIONS - Must use :deep() because D3 creates these elements outside Vue */
:deep(.node-shape) {
    transition: all 0.3s ease;
    cursor: pointer;
    transform-box: fill-box; /* Critical for SVG transforms */
    transform-origin: center;
    /* Subtle breathing animation for all nodes */
    animation: bubble-float 3s ease-in-out infinite;
}

/* Subtle floating/breathing for all nodes */
@keyframes bubble-float {
  0%, 100% { transform: scale(1); }
  50% { transform: scale(1.08); }
}

/* Hover - Strong Glow & Wobble */
:deep(.node-hovered) {
    /* Subtle glow effect */
    filter: drop-shadow(0 0 6px currentColor) drop-shadow(0 0 10px rgba(255, 255, 255, 0.4)); 
    /* More pronounced wobble animation on hover */
    animation: bubble-wobble 0.6s ease-in-out infinite !important; 
}

@keyframes bubble-wobble {
  0% { transform: scale(1); }
  25% { transform: scale(1.3); }
  50% { transform: scale(0.9); }
  75% { transform: scale(1.2); }
  100% { transform: scale(1); }
}

.legend-dot { width: 10px; height: 10px; border-radius: 50%; display: inline-block; margin-right: 5px; }
.graph-legend { margin-top: 10px; color: #aaa; font-size: 14px; position: absolute; bottom: 20px; left: 20px; z-index: 100;}
</style>
