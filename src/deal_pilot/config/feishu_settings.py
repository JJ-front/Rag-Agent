from deal_pilot.config.base_settings import BaseSettingsWithEnv


class FeishuSettings(BaseSettingsWithEnv):
    app_id: str = ""
    app_secret: str = ""
    # 飞书事件监听是可选的：默认关闭，普通对话 / RAG 不依赖飞书。
    events_enabled: bool = False

    model_config = {"env_prefix": "FEISHU_"}


feishu_settings = FeishuSettings()
