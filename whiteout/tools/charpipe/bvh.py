"""Minimal BVH parser + FK (numpy). CMU data: https://mocap.cs.cmu.edu (free for any use)."""
import numpy as np, re, math


class BVH:
    def __init__(self, path):
        toks = open(path).read().replace("\t", " ").split("\n")
        self.names, self.parent, self.offset, self.chan, self.endsite = [], [], [], [], {}
        stack = []; i = 0
        while i < len(toks):
            ln = toks[i].strip(); i += 1
            if ln.startswith("MOTION"):
                break
            p = ln.split()
            if not p: continue
            if p[0] in ("ROOT", "JOINT"):
                self.names.append(p[1]); self.parent.append(stack[-1] if stack else -1)
                self.offset.append(None); self.chan.append(None)
                stack.append(len(self.names) - 1); cur_end = False
            elif p[0] == "End":
                stack.append(-2); cur_end = True
            elif p[0] == "OFFSET":
                off = [float(v) for v in p[1:4]]
                if stack[-1] == -2:
                    self.endsite[stack[-2]] = off
                else:
                    self.offset[stack[-1]] = off
            elif p[0] == "CHANNELS":
                self.chan[stack[-1]] = p[2:]
            elif p[0] == "}":
                stack.pop()
        while not toks[i].strip().startswith("Frames"): i += 1
        nf = int(toks[i].split()[1]); ft = float(toks[i + 1].split()[2]); i += 2
        self.dt = ft
        data = np.array([[float(v) for v in toks[i + k].split()] for k in range(nf)])
        self.nframes = nf
        self.offset = np.array(self.offset)
        # parse channels
        col = 0; self.pos = None; self.rot = []   # rot: list of (frames,3 degrees) + order
        self.order = []
        for j, ch in enumerate(self.chan):
            vals = data[:, col:col + len(ch)]; col += len(ch)
            if any(c.endswith("position") for c in ch):
                self.pos = vals[:, [ch.index("Xposition"), ch.index("Yposition"), ch.index("Zposition")]]
            rc = [c for c in ch if c.endswith("rotation")]
            order = "".join(c[0] for c in rc)
            self.order.append(order)
            self.rot.append(vals[:, [ch.index(c) for c in rc]] if rc else np.zeros((nf, 3)))

    @staticmethod
    def _R(axis, a):
        c, s = np.cos(a), np.sin(a)
        n = len(a); R = np.zeros((n, 3, 3)); R[:, :, :] = np.eye(3)
        if axis == "X":
            R[:, 1, 1] = c; R[:, 1, 2] = -s; R[:, 2, 1] = s; R[:, 2, 2] = c
        elif axis == "Y":
            R[:, 0, 0] = c; R[:, 0, 2] = s; R[:, 2, 0] = -s; R[:, 2, 2] = c
        else:
            R[:, 0, 0] = c; R[:, 0, 1] = -s; R[:, 1, 0] = s; R[:, 1, 1] = c
        return R

    def local_rots(self):
        out = []
        for j in range(len(self.names)):
            order = self.order[j]; ang = np.radians(self.rot[j])
            R = None
            for k, ax in enumerate(order):
                Rk = self._R(ax, ang[:, k])
                R = Rk if R is None else R @ Rk
            out.append(R if R is not None else np.tile(np.eye(3), (self.nframes, 1, 1)))
        return out

    def world_rots(self):
        L = self.local_rots(); W = []
        for j, p in enumerate(self.parent):
            W.append(L[j] if p < 0 else W[p] @ L[j])
        return W

    def idx(self, name):
        return self.names.index(name)

    def rest_world_pos(self):
        P = np.zeros((len(self.names), 3))
        for j, p in enumerate(self.parent):
            P[j] = self.offset[j] + (P[p] if p >= 0 else 0)
        return P
