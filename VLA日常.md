**这个会话要结束了，请写一份交接文档存到HANDOFF.md：我们在做什么任务，已经完成了什么、有哪些踩过的坑绝对不要踩的坑。写给一个完全没有上下文的新对话看。**

新对话与某个会话相关：先读HANDOOF.dm

### FluxVLA记录

#### 基于Pi0.5的强化学习

标准 BC 把每条演示同等对待。长程操作里有大量「停顿、失败、回退」帧，这些帧会把策略往坏方向拉。仓库的做法是：

1. 训练一个奖励模型，给每一帧估一个任务进度 `progress ∈ [0, 1]`。
2. 看未来一个动作 chunk 内进度有没有涨：`delta = progress[t + 50] - progress[t]`（π0.5 的 `n_action_steps=50`）。
3. 用 `delta` 生成 `sample_weight`，乘到 π0.5 的 flow matching MSE 上。

```
专家/DAgger 数据
        │
        ├─[A] 普通 SFT：π0.5 行为克隆
        │
        └─[B] 奖励模型 ARM / SARM
                │
                ▼
          每帧 progress
                │
                ▼
          RA-BC / AW-BC 样本权重
                │
                ▼
          再训一次 π0.5（加权 BC ≈ 离线 RL）
```

这更接近 advantage-weighted imitation / offline RL，不是和环境滚数据、反传策略梯度。

#### 两种奖励模型：ARM 还是 SARM

|         | ARM（更适合你现在的数据）                                   | SARM                                  |
| ------- | ------------------------------------------------ | ------------------------------------- |
| 监督      | parquet 里每帧一个标量 `progress`                       | 每条 episode 的子任务起止标注                   |
| 模型输出    | 相邻帧相对优势 `{回退, 停滞, 前进}` + 是否完成                    | 当前处于哪一阶段 + 阶段内进度                      |
| 标注成本    | 需要一段带 GT progress 的数据来训奖励模型；之后可对无标签的 policy 数据推理 | 要写 sparse/dense stage，或用 Qwen3-VL 自动标 |
| 接到 π0.5 | `ArmRABCWeighter` / `ArmAWBCWeighter`            | `SarmRABCWeighter`                    |

你的 `STAMP` / `GET_PASSPORT` 目前没有 `progress` 列，也没有 SARM 子任务标注。要用这套「类 RL」流程，通常走 ARM：先找或标一份带 progress 的数据训奖励模型，再对你的 policy 数据推理出进度。

#### RA-BC 和 AW-BC 差在哪

权重映射在 `fluxvla.weighters` 里：

- RA-BC：只看进度增量  
  `delta > 0.01` → 权重 1；`delta < 0` → 权重 0（丢掉回退样本）；中间软加权。
- AW-BC：在 RA-BC 上再乘 `episode_length / 平均长度`。轨迹长短差很大（例如 DAgger 混了短失败和长成功）时用它。

#### 推荐落地顺序（对接lerobot v3）

第 0 步：先做 π0.5 监督微调。 这是主路径。从 `pi05_base` 出发，改相机名、state/action 维、数据路径，训 STAMP / GET_PASSPORT。没有这一步，后面的加权没有好的策略初始化。

第 1 步：训 ARM 奖励模型。 **需要一份带每帧 `progress` 的 LeRobot 数据**（官方示例：`ARM_manual_test_10Episodes_lerobotv3.0`）。配置是 `configs/arm/arm_clip_aloha_example.py`，视觉骨干是 CLIP。相机名要改成你的，例如 STAMP 的 `observation.images.head_left`。

第 2 步：对 policy 数据推理进度。 不要求 policy 数据自带 `progress`：

```sh
python scripts/compute_arm_awbc_progress.py \

--config configs/arm/arm_clip_aloha_example.py \

--ckpt-path ./work_dirs/arm/checkpoints/latest-checkpoint.pt \

--output-path ./work_dirs/arm_awbc/arm_progress.parquet \

--stride 150 \

--cfg-options inference_dataset.data_root_path=./data/STAMP/STAMP_lerobot_6d_813_v2_1
```

建议先用 `scripts/infer_arm_progress.py` 可视化一条 episode，确认进度曲线合理，再拿去加权训练。

第 3 步：把权重接到 π0.5 配置。 在 `ParquetDataset` 上：

1. `expose_index=True`
2. 在 `ProcessParquetInputs` 之前插入 `AttachRABCWeight`
3. collator 的 `keys` 加上 `'sample_weight'`
4. `chunk_size=50`（对齐 π0.5 动作地平线）

```python
rabc_weighter = dict(

type='ArmRABCWeighter', # 轨迹长短差大就改成 ArmAWBCWeighter

progress_path='./work_dirs/arm_awbc/arm_progress.parquet',

chunk_size=50,

index_key='index',

)
```

然后照常 `torchrun scripts/train.py --config ...`，π0.5 会吃到加权 loss。

#### 和「真 RL」的边界

仓库里和强化学习相邻、但不是策略梯度的东西还有：

- FluxDAgger（独立仓库）：用 π0.5 在真机/仿真 rollout，人在失败时接管，把新数据并回 BC。这是交互式模仿，不是 RL。
- RTC：推理时用已执行动作当 prefix，保证 chunk 之间连续，和训练算法无关。

```
pick stamp
move to paper
press stamp


reach stamp
grasp stamp
lift stamp
align to paper
press down
lift off
```
