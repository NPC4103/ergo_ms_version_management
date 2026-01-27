/**
 * Graph Utilities for Commit Graph Visualization
 * Calculates centrality metrics for nodes in a commit graph
 */

/**
 * Calculate Degree Centrality - number of connections per node
 * @param {Array} nodes - Array of nodes with id property
 * @param {Array} links - Array of links with source/target properties
 * @returns {Map} Map of nodeId -> degree
 */
export function calculateDegreeCentrality(nodes, links) {
    const degree = new Map();

    // Initialize all nodes with 0 degree
    nodes.forEach(node => degree.set(node.id, 0));

    // Count connections
    links.forEach(link => {
        const sourceId = typeof link.source === 'object' ? link.source.id : link.source;
        const targetId = typeof link.target === 'object' ? link.target.id : link.target;

        degree.set(sourceId, (degree.get(sourceId) || 0) + 1);
        degree.set(targetId, (degree.get(targetId) || 0) + 1);
    });

    return degree;
}

/**
 * Calculate Betweenness Centrality using BFS
 * Measures how often a node appears on shortest paths between other nodes
 * @param {Array} nodes - Array of nodes with id property
 * @param {Array} links - Array of links with source/target properties
 * @returns {Map} Map of nodeId -> betweenness score
 */
export function calculateBetweennessCentrality(nodes, links) {
    const betweenness = new Map();
    nodes.forEach(node => betweenness.set(node.id, 0));

    // Build adjacency list
    const adjacency = new Map();
    nodes.forEach(node => adjacency.set(node.id, []));

    links.forEach(link => {
        const sourceId = typeof link.source === 'object' ? link.source.id : link.source;
        const targetId = typeof link.target === 'object' ? link.target.id : link.target;

        adjacency.get(sourceId)?.push(targetId);
        adjacency.get(targetId)?.push(sourceId);
    });

    // For each node, perform BFS and count paths
    nodes.forEach(source => {
        const queue = [source.id];
        const distances = new Map([[source.id, 0]]);
        const paths = new Map([[source.id, 1]]);
        const predecessors = new Map();

        // BFS
        while (queue.length > 0) {
            const current = queue.shift();
            const neighbors = adjacency.get(current) || [];

            neighbors.forEach(neighbor => {
                if (!distances.has(neighbor)) {
                    distances.set(neighbor, distances.get(current) + 1);
                    queue.push(neighbor);
                }

                if (distances.get(neighbor) === distances.get(current) + 1) {
                    paths.set(neighbor, (paths.get(neighbor) || 0) + paths.get(current));
                    if (!predecessors.has(neighbor)) {
                        predecessors.set(neighbor, []);
                    }
                    predecessors.get(neighbor).push(current);
                }
            });
        }

        // Accumulate betweenness
        const delta = new Map();
        nodes.forEach(node => delta.set(node.id, 0));

        // Process nodes in reverse order of distance
        const sortedNodes = [...distances.entries()]
            .sort((a, b) => b[1] - a[1])
            .map(([id]) => id);

        sortedNodes.forEach(nodeId => {
            const preds = predecessors.get(nodeId) || [];
            preds.forEach(pred => {
                const pathRatio = (paths.get(pred) || 1) / (paths.get(nodeId) || 1);
                delta.set(pred, delta.get(pred) + pathRatio * (1 + delta.get(nodeId)));
            });

            if (nodeId !== source.id) {
                betweenness.set(nodeId, betweenness.get(nodeId) + delta.get(nodeId));
            }
        });
    });

    // Normalize
    const n = nodes.length;
    if (n > 2) {
        const scale = 1 / ((n - 1) * (n - 2));
        betweenness.forEach((value, key) => {
            betweenness.set(key, value * scale);
        });
    }

    return betweenness;
}

/**
 * Calculate Closeness Centrality
 * Measures how close a node is to all other nodes
 * @param {Array} nodes - Array of nodes with id property
 * @param {Array} links - Array of links with source/target properties
 * @returns {Map} Map of nodeId -> closeness score
 */
export function calculateClosenessCentrality(nodes, links) {
    const closeness = new Map();

    // Build adjacency list
    const adjacency = new Map();
    nodes.forEach(node => adjacency.set(node.id, []));

    links.forEach(link => {
        const sourceId = typeof link.source === 'object' ? link.source.id : link.source;
        const targetId = typeof link.target === 'object' ? link.target.id : link.target;

        adjacency.get(sourceId)?.push(targetId);
        adjacency.get(targetId)?.push(sourceId);
    });

    nodes.forEach(source => {
        // BFS to find distances
        const queue = [source.id];
        const distances = new Map([[source.id, 0]]);

        while (queue.length > 0) {
            const current = queue.shift();
            const neighbors = adjacency.get(current) || [];

            neighbors.forEach(neighbor => {
                if (!distances.has(neighbor)) {
                    distances.set(neighbor, distances.get(current) + 1);
                    queue.push(neighbor);
                }
            });
        }

        // Sum of distances
        let totalDistance = 0;
        distances.forEach(dist => { totalDistance += dist; });

        // Closeness = (n-1) / sum of distances
        const reachable = distances.size - 1;
        closeness.set(source.id, reachable > 0 ? reachable / totalDistance : 0);
    });

    return closeness;
}

/**
 * Calculate PageRank using power iteration
 * @param {Array} nodes - Array of nodes with id property
 * @param {Array} links - Array of links with source/target properties
 * @param {number} damping - Damping factor (default 0.85)
 * @param {number} iterations - Number of iterations (default 20)
 * @returns {Map} Map of nodeId -> pagerank score
 */
export function calculatePageRank(nodes, links, damping = 0.85, iterations = 20) {
    const n = nodes.length;
    if (n === 0) return new Map();

    const pagerank = new Map();
    const outDegree = new Map();

    // Initialize
    nodes.forEach(node => {
        pagerank.set(node.id, 1 / n);
        outDegree.set(node.id, 0);
    });

    // Build outgoing links count
    links.forEach(link => {
        const sourceId = typeof link.source === 'object' ? link.source.id : link.source;
        outDegree.set(sourceId, (outDegree.get(sourceId) || 0) + 1);
    });

    // Build incoming links map
    const inLinks = new Map();
    nodes.forEach(node => inLinks.set(node.id, []));

    links.forEach(link => {
        const sourceId = typeof link.source === 'object' ? link.source.id : link.source;
        const targetId = typeof link.target === 'object' ? link.target.id : link.target;

        inLinks.get(targetId)?.push(sourceId);
    });

    // Power iteration
    for (let i = 0; i < iterations; i++) {
        const newRank = new Map();

        nodes.forEach(node => {
            let rank = (1 - damping) / n;

            const incoming = inLinks.get(node.id) || [];
            incoming.forEach(sourceId => {
                const sourceOutDegree = outDegree.get(sourceId) || 1;
                rank += damping * (pagerank.get(sourceId) || 0) / sourceOutDegree;
            });

            newRank.set(node.id, rank);
        });

        // Update ranks
        newRank.forEach((value, key) => pagerank.set(key, value));
    }

    return pagerank;
}

/**
 * Normalize metrics to 0-1 range
 * @param {Map} metrics - Map of nodeId -> metric value
 * @returns {Map} Normalized map
 */
export function normalizeMetrics(metrics) {
    const values = [...metrics.values()];
    const min = Math.min(...values);
    const max = Math.max(...values);
    const range = max - min || 1;

    const normalized = new Map();
    metrics.forEach((value, key) => {
        normalized.set(key, (value - min) / range);
    });

    return normalized;
}

/**
 * Calculate all centrality metrics for a graph
 * @param {Array} nodes - Array of nodes with id property
 * @param {Array} links - Array of links with source/target properties
 * @returns {Object} Object containing all normalized metrics
 */
export function calculateAllMetrics(nodes, links) {
    const degree = normalizeMetrics(calculateDegreeCentrality(nodes, links));
    const betweenness = normalizeMetrics(calculateBetweennessCentrality(nodes, links));
    const closeness = normalizeMetrics(calculateClosenessCentrality(nodes, links));
    const pagerank = normalizeMetrics(calculatePageRank(nodes, links));

    // Apply metrics to nodes
    nodes.forEach(node => {
        node.metrics = {
            degree: degree.get(node.id) || 0,
            betweenness: betweenness.get(node.id) || 0,
            closeness: closeness.get(node.id) || 0,
            pagerank: pagerank.get(node.id) || 0,
            // Combined importance score
            importance: (
                (degree.get(node.id) || 0) * 0.25 +
                (betweenness.get(node.id) || 0) * 0.35 +
                (closeness.get(node.id) || 0) * 0.15 +
                (pagerank.get(node.id) || 0) * 0.25
            )
        };
    });

    return { degree, betweenness, closeness, pagerank };
}
